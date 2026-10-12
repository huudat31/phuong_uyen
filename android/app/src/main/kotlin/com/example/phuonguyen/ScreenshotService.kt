package com.example.phuonguyen

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

class ScreenshotService : Service() {

    companion object {
        private const val TAG = "SelfMonitorScreen"
        var isRunning: Boolean = false

        // Giữ token MediaProjection trực tiếp trong cùng process để tránh thất lạc binder khi IPC
        var screenCaptureResultCode: Int = -1
        var screenCaptureResultData: Intent? = null

        const val ACTION_START = "ACTION_START"
        const val ACTION_STOP = "ACTION_STOP"
        const val EXTRA_RESULT_CODE = "EXTRA_RESULT_CODE"
        const val EXTRA_RESULT_DATA = "EXTRA_RESULT_DATA"
        const val EXTRA_INTERVAL_SECONDS = "EXTRA_INTERVAL_SECONDS"

        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "screenshot_monitor_channel"
    }

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var wakeLock: PowerManager.WakeLock? = null

    private val handler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private lateinit var dbHelper: DbHelper

    private var screenWidth: Int = 0
    private var screenHeight: Int = 0
    private var screenDensity: Int = 0
    private var intervalMillis: Long = 15_000L // Mặc định 15 giây

    private val captureRunnable = object : Runnable {
        override fun run() {
            if (!isRunning || mediaProjection == null) return
            captureCurrentFrame()
            handler.postDelayed(this, intervalMillis)
        }
    }

    override fun onCreate() {
        super.onCreate()
        dbHelper = DbHelper(this)
        createNotificationChannel()

        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
        wakeLock = powerManager?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "SelfMonitor:ScreenshotWakeLock")
        Log.d(TAG, "ScreenshotService onCreate")
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START

        when (action) {
            ACTION_START -> {
                val intentCode = intent?.getIntExtra(EXTRA_RESULT_CODE, -1) ?: -1
                val intentData: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent?.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent?.getParcelableExtra(EXTRA_RESULT_DATA)
                }

                val resultCode = if (intentCode != -1) intentCode else screenCaptureResultCode
                val resultData = intentData ?: screenCaptureResultData

                val intervalSec = intent?.getIntExtra(EXTRA_INTERVAL_SECONDS, 15) ?: 15
                intervalMillis = (intervalSec.coerceAtLeast(5) * 1000).toLong()

                if (resultCode != -1 && resultData != null) {
                    startForegroundWithNotification()
                    initMediaProjectionAndDisplay(resultCode, resultData)
                    isRunning = true
                    Log.d(TAG, "ScreenshotService started with interval=${intervalMillis}ms")

                    // Chụp khung hình đầu tiên sau 1.5 giây, sau đó lặp lại theo chu kỳ
                    handler.removeCallbacks(captureRunnable)
                    handler.postDelayed(captureRunnable, 1500L)
                } else {
                    Log.e(TAG, "Missing MediaProjection permission data, stopping service")
                    stopSelf()
                }
            }
            ACTION_STOP -> {
                Log.d(TAG, "Received ACTION_STOP")
                stopSelfService()
            }
        }

        // START_STICKY để Android giữ service chạy ngầm kể cả khi Activity bị tắt
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        Log.d(TAG, "App task removed from recents. Keeping ScreenshotService running in background.")
    }

    private fun startForegroundWithNotification() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun initMediaProjectionAndDisplay(resultCode: Int, resultData: Intent) {
        try {
            val projectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            mediaProjection = projectionManager.getMediaProjection(resultCode, resultData)

            if (mediaProjection == null) {
                Log.e(TAG, "Failed to obtain MediaProjection from token")
                return
            }

            mediaProjection?.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {
                    super.onStop()
                    Log.w(TAG, "MediaProjection stopped by system")
                    stopSelfService()
                }
            }, handler)

            setupScreenMetrics()
            setupVirtualDisplay()
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing MediaProjection", e)
        }
    }

    private fun setupScreenMetrics() {
        val windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val windowMetrics = windowManager.currentWindowMetrics
            val bounds = windowMetrics.bounds
            screenWidth = bounds.width()
            screenHeight = bounds.height()
            screenDensity = resources.configuration.densityDpi
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay.getRealMetrics(metrics)
            screenWidth = metrics.widthPixels
            screenHeight = metrics.heightPixels
            screenDensity = metrics.densityDpi
        }

        // Đảm bảo kích thước chẵn
        if (screenWidth % 2 != 0) screenWidth -= 1
        if (screenHeight % 2 != 0) screenHeight -= 1
        Log.d(TAG, "Screen dimensions: ${screenWidth}x${screenHeight}, density=$screenDensity")
    }

    private fun setupVirtualDisplay() {
        val projection = mediaProjection ?: return
        if (screenWidth <= 0 || screenHeight <= 0) return

        try {
            virtualDisplay?.release()
            imageReader?.close()

            imageReader = ImageReader.newInstance(screenWidth, screenHeight, PixelFormat.RGBA_8888, 4)
            virtualDisplay = projection.createVirtualDisplay(
                "SelfMonitorVirtualDisplay",
                screenWidth,
                screenHeight,
                screenDensity,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                imageReader?.surface,
                null,
                handler
            )
            Log.d(TAG, "VirtualDisplay created successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create VirtualDisplay", e)
        }
    }

    private fun captureCurrentFrame() {
        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
        if (powerManager?.isInteractive == false) {
            return
        }

        val reader = imageReader ?: return
        wakeLock?.acquire(3000L) // Giữ wake lock trong tối đa 3 giây khi chụp và ghi file

        executor.execute {
            var image: android.media.Image? = null
            try {
                image = reader.acquireLatestImage() ?: try {
                    reader.acquireNextImage()
                } catch (_: Exception) {
                    null
                }
                if (image == null) {
                    Log.d(TAG, "No new frame in buffer, waiting for next interval")
                    return@execute
                }

                val planes = image.planes
                val buffer = planes[0].buffer
                buffer.rewind()
                val pixelStride = planes[0].pixelStride
                val rowStride = planes[0].rowStride
                val rowPadding = rowStride - pixelStride * screenWidth

                val bitmapWidth = screenWidth + if (pixelStride > 0) rowPadding / pixelStride else 0
                val bitmap = Bitmap.createBitmap(bitmapWidth, screenHeight, Bitmap.Config.ARGB_8888)
                bitmap.copyPixelsFromBuffer(buffer)

                val finalBitmap = if (bitmapWidth > screenWidth) {
                    val cropped = Bitmap.createBitmap(bitmap, 0, 0, screenWidth, screenHeight)
                    bitmap.recycle()
                    cropped
                } else {
                    bitmap
                }

                // Kiểm tra nếu là màn hình đen xì (tắt màn hình/khoá máy) thì bỏ qua, không lưu và không gửi
                if (TelegramSender.isPureBlackBitmap(finalBitmap)) {
                    Log.d(TAG, "Foreground frame is pure black (screen off/sleep). Discarding.")
                    finalBitmap.recycle()
                    return@execute
                }

                val dir = File(filesDir, "screenshots")
                if (!dir.exists()) dir.mkdirs()
                val file = File(dir, "shot_${System.currentTimeMillis()}.jpg")
                FileOutputStream(file).use { out ->
                    finalBitmap.compress(Bitmap.CompressFormat.JPEG, 75, out)
                }
                file.setReadable(true, false)
                finalBitmap.recycle()

                Log.d(TAG, "Screenshot saved successfully: ${file.absolutePath} (${file.length()} bytes)")
                dbHelper.insertScreenshot(file.absolutePath)

                // Tự động đẩy lên Telegram và dọn dẹp bộ nhớ Máy 1 nếu đã kích hoạt
                TelegramSender.syncPendingData(applicationContext)
            } catch (e: Exception) {
                Log.e(TAG, "Error processing screen frame", e)
            } finally {
                try {
                    image?.close()
                } catch (e: Exception) {
                    // Ignore
                }
            }
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Giám sát màn hình phương uyên",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Hiển thị thông báo khi dịch vụ chụp màn hình đang hoạt động chạy ngầm"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("phương uyên đang chạy ngầm")
            .setContentText("Dịch vụ tự động chụp màn hình định kỳ đang hoạt động")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
    }

    private fun stopSelfService() {
        isRunning = false
        handler.removeCallbacks(captureRunnable)

        try {
            virtualDisplay?.release()
            virtualDisplay = null
            imageReader?.close()
            imageReader = null
            mediaProjection?.stop()
            mediaProjection = null
        } catch (e: Exception) {
            Log.e(TAG, "Error cleaning up projection", e)
        }

        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (e: Exception) {
            // Ignore
        }

        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        Log.d(TAG, "ScreenshotService stopped")
    }

    override fun onDestroy() {
        super.onDestroy()
        stopSelfService()
        executor.shutdown()
        Log.d(TAG, "ScreenshotService onDestroy")
    }
}
