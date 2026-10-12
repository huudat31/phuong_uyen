package com.example.phuonguyen

import android.accessibilityservice.AccessibilityServiceInfo
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.text.TextUtils
import android.util.Log
import android.view.accessibility.AccessibilityManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "SelfMonitorMain"
        private const val CHANNEL = "self_monitor_app/native"
        private const val REQUEST_CODE_SCREEN_CAPTURE = 1002
    }

    private var pendingScreenCaptureResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAccessibilityServiceEnabled" -> {
                    result.success(checkAccessibilityServiceEnabled())
                }
                "openAccessibilitySettings" -> {
                    openAccessibilitySettings()
                    result.success(null)
                }
                "requestScreenCapturePermission" -> {
                    if (pendingScreenCaptureResult != null) {
                        result.error("ALREADY_REQUESTING", "Đang chờ người dùng phản hồi cấp quyền", null)
                        return@setMethodCallHandler
                    }
                    val mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as? MediaProjectionManager
                    if (mediaProjectionManager == null) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    pendingScreenCaptureResult = result
                    startActivityForResult(mediaProjectionManager.createScreenCaptureIntent(), REQUEST_CODE_SCREEN_CAPTURE)
                }
                "startScreenshotService" -> {
                    if (ScreenshotService.screenCaptureResultCode != Activity.RESULT_OK || ScreenshotService.screenCaptureResultData == null) {
                        result.error("NO_PERMISSION", "Chưa cấp quyền chụp màn hình MediaProjection", null)
                        return@setMethodCallHandler
                    }
                    val intervalSeconds = call.argument<Int>("intervalSeconds") ?: 15
                    val intent = Intent(this, ScreenshotService::class.java).apply {
                        action = ScreenshotService.ACTION_START
                        putExtra(ScreenshotService.EXTRA_RESULT_CODE, ScreenshotService.screenCaptureResultCode)
                        putExtra(ScreenshotService.EXTRA_RESULT_DATA, ScreenshotService.screenCaptureResultData)
                        putExtra(ScreenshotService.EXTRA_INTERVAL_SECONDS, intervalSeconds)
                    }
                    ContextCompat.startForegroundService(this, intent)
                    result.success(null)
                }
                "stopScreenshotService" -> {
                    val intent = Intent(this, ScreenshotService::class.java).apply {
                        action = ScreenshotService.ACTION_STOP
                    }
                    startService(intent)
                    result.success(null)
                }
                "isScreenshotServiceRunning" -> {
                    result.success(ScreenshotService.isRunning)
                }
                "isIgnoringBatteryOptimizations" -> {
                    result.success(isIgnoringBatteryOptimizations())
                }
                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBatteryOptimizations()
                    result.success(null)
                }
                "saveTelegramConfig" -> {
                    val botToken = call.argument<String>("botToken") ?: ""
                    val chatId = call.argument<String>("chatId") ?: ""
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    TelegramSender.saveConfig(this, botToken, chatId, enabled)
                    result.success(true)
                }
                "getTelegramConfig" -> {
                    val (botToken, chatId, enabled) = TelegramSender.getConfig(this)
                    result.success(mapOf(
                        "botToken" to botToken,
                        "chatId" to chatId,
                        "enabled" to enabled
                    ))
                }
                "testTelegramConnection" -> {
                    val botToken = call.argument<String>("botToken") ?: ""
                    val chatId = call.argument<String>("chatId") ?: ""
                    TelegramSender.testConnectionAsync(botToken, chatId) { ok, msg ->
                        result.success(mapOf(
                            "success" to ok,
                            "message" to msg
                        ))
                    }
                }
                "syncTelegramNow" -> {
                    TelegramSender.syncPendingData(this) { sentTexts, sentPhotos, error ->
                        result.success(mapOf(
                            "sentTexts" to sentTexts,
                            "sentPhotos" to sentPhotos,
                            "error" to (error ?: "")
                        ))
                    }
                }
                "getDatabaseStats" -> {
                    val counts = DbHelper(this).getCounts()
                    result.success(mapOf(
                        "textCount" to counts.first,
                        "screenshotCount" to counts.second
                    ))
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_SCREEN_CAPTURE) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                ScreenshotService.screenCaptureResultCode = resultCode
                ScreenshotService.screenCaptureResultData = data
                Log.d(TAG, "Screen capture permission GRANTED")
                pendingScreenCaptureResult?.success(true)
            } else {
                Log.w(TAG, "Screen capture permission DENIED")
                pendingScreenCaptureResult?.success(false)
            }
            pendingScreenCaptureResult = null
        }
    }

    private fun checkAccessibilityServiceEnabled(): Boolean {
        // 1. Kiểm tra trực tiếp biến trạng thái của service nếu đang chạy
        if (MonitorAccessibilityService.isRunning) return true

        // 2. Kiểm tra danh sách dịch vụ trợ năng đã kích hoạt qua AccessibilityManager
        try {
            val am = getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager
            val enabledServices = am?.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
            if (enabledServices != null) {
                for (service in enabledServices) {
                    val serviceInfo = service.resolveInfo?.serviceInfo
                    if (serviceInfo != null && serviceInfo.packageName == packageName &&
                        serviceInfo.name.contains("MonitorAccessibilityService")) {
                        return true
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error checking AccessibilityManager", e)
        }

        // 3. Kiểm tra qua Settings.Secure
        try {
            val enabledServicesSetting = Settings.Secure.getString(
                contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: return false

            val colonSplitter = TextUtils.SimpleStringSplitter(':')
            colonSplitter.setString(enabledServicesSetting)
            while (colonSplitter.hasNext()) {
                val component = colonSplitter.next()
                if (component.contains(packageName) && component.contains("MonitorAccessibilityService")) {
                    return true
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error checking Settings.Secure", e)
        }

        return false
    }

    private fun openAccessibilitySettings() {
        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return true
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            pm.isIgnoringBatteryOptimizations(packageName)
        } else {
            true
        }
    }

    private fun requestIgnoreBatteryOptimizations() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
            } catch (e: Exception) {
                try {
                    val fallback = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(fallback)
                } catch (ex: Exception) {
                    Log.e(TAG, "Failed to open battery optimization settings", ex)
                }
            }
        }
    }
}
