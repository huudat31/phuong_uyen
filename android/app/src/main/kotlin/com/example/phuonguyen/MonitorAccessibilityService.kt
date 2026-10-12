package com.example.phuonguyen

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.util.Log
import android.view.accessibility.AccessibilityEvent

class MonitorAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "SelfMonitorAcc"
        var isRunning: Boolean = false
    }

    private lateinit var dbHelper: DbHelper

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
                }
            }

            AccessibilityEvent.TYPE_VIEW_CLICKED -> {
                val text = event.text?.joinToString(" ") { it.toString() }?.trim() ?: ""
                val desc = event.contentDescription?.toString()?.trim() ?: ""
                val clickedItem = if (text.isNotEmpty()) text else desc
                if (clickedItem.isNotEmpty()) {
                    Log.d(TAG, "Captured click from [$pkg]: $clickedItem")
                    dbHelper.insertTextLog(pkg, "[Click] $clickedItem")
                }
            }
        }
    }

    override fun onInterrupt() {
        Log.w(TAG, "MonitorAccessibilityService onInterrupt")
    }

    override fun onDestroy() {
        super.onDestroy()
        isRunning = false
        Log.d(TAG, "MonitorAccessibilityService onDestroy")
    }
}
