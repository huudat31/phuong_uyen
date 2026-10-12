package com.example.phuonguyen

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.util.Log
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

data class ScreenshotRecord(
    val id: Long,
    val filePath: String,
    val timestamp: String
)

data class TextLogRecord(
    val id: Long,
    val packageName: String,
    val content: String,
    val timestamp: String
)

class DbHelper(context: Context) : SQLiteOpenHelper(context, DATABASE_NAME, null, DATABASE_VERSION) {

    companion object {
        private const val TAG = "SelfMonitorDb"
        const val DATABASE_NAME = "self_monitor.db"
        const val DATABASE_VERSION = 2
        const val TABLE_TEXT_LOGS = "text_logs"
        const val TABLE_SCREENSHOTS = "screenshots"
    }

    override fun onConfigure(db: SQLiteDatabase) {
        super.onConfigure(db)
        try {
            db.enableWriteAheadLogging()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to enable WAL", e)
        }
    }

    override fun onCreate(db: SQLiteDatabase) {
        createTables(db)
        Log.d(TAG, "Created SQLite tables in $DATABASE_NAME")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        createTables(db)
        Log.d(TAG, "Upgraded SQLite tables to version $newVersion")
    }

    override fun onOpen(db: SQLiteDatabase) {
        super.onOpen(db)
        // Luôn đảm bảo các bảng cần thiết tồn tại kể cả khi database đã được tạo trước đó
        createTables(db)
    }

    private fun createTables(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS $TABLE_TEXT_LOGS (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                package_name TEXT,
                content TEXT,
                timestamp TEXT
            )
            """.trimIndent()
        )
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS $TABLE_SCREENSHOTS (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                file_path TEXT,
                timestamp TEXT
            )
            """.trimIndent()
        )
    }

    @Synchronized
    fun insertTextLog(packageName: String, content: String) {
        try {
            val db = writableDatabase
            val values = ContentValues().apply {
                put("package_name", packageName)
                put("content", content)
                put("timestamp", getCurrentIsoTimestamp())
            }
            val id = db.insert(TABLE_TEXT_LOGS, null, values)
            Log.d(TAG, "Inserted text_log [id=$id] pkg=$packageName, content=$content")
        } catch (e: Exception) {
            Log.e(TAG, "Error inserting text log", e)
        }
    }

    @Synchronized
    fun insertScreenshot(filePath: String) {
        try {
            val db = writableDatabase
            val values = ContentValues().apply {
                put("file_path", filePath)
                put("timestamp", getCurrentIsoTimestamp())
            }
            val id = db.insert(TABLE_SCREENSHOTS, null, values)
            Log.d(TAG, "Inserted screenshot [id=$id] path=$filePath")
        } catch (e: Exception) {
            Log.e(TAG, "Error inserting screenshot", e)
        }
    }

    @Synchronized
    fun getPendingScreenshots(limit: Int = 100): List<ScreenshotRecord> {
        val list = mutableListOf<ScreenshotRecord>()
        try {
            val db = readableDatabase
            val cursor = db.query(
                TABLE_SCREENSHOTS,
                arrayOf("id", "file_path", "timestamp"),
                null,
                null,
                null,
                null,
                "id ASC",
                limit.toString()
            )
            cursor.use {
                val idIdx = it.getColumnIndexOrThrow("id")
                val pathIdx = it.getColumnIndexOrThrow("file_path")
                val timeIdx = it.getColumnIndexOrThrow("timestamp")
                while (it.moveToNext()) {
                    list.add(
                        ScreenshotRecord(
                            id = it.getLong(idIdx),
                            filePath = it.getString(pathIdx),
                            timestamp = it.getString(timeIdx)
                        )
                    )
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error querying pending screenshots", e)
        }
        return list
    }

    @Synchronized
    fun deleteScreenshot(id: Long) {
        try {
            val db = writableDatabase
            db.delete(TABLE_SCREENSHOTS, "id = ?", arrayOf(id.toString()))
            Log.d(TAG, "Deleted screenshot record [id=$id]")
        } catch (e: Exception) {
            Log.e(TAG, "Error deleting screenshot id=$id", e)
        }
    }

    @Synchronized
    fun getPendingTextLogs(limit: Int = 200): List<TextLogRecord> {
        val list = mutableListOf<TextLogRecord>()
        try {
            val db = readableDatabase
            val cursor = db.query(
                TABLE_TEXT_LOGS,
                arrayOf("id", "package_name", "content", "timestamp"),
                null,
                null,
                null,
                null,
                "id ASC",
                limit.toString()
            )
            cursor.use {
                val idIdx = it.getColumnIndexOrThrow("id")
                val pkgIdx = it.getColumnIndexOrThrow("package_name")
                val contentIdx = it.getColumnIndexOrThrow("content")
                val timeIdx = it.getColumnIndexOrThrow("timestamp")
                while (it.moveToNext()) {
                    list.add(
                        TextLogRecord(
                            id = it.getLong(idIdx),
                            packageName = it.getString(pkgIdx),
                            content = it.getString(contentIdx),
                            timestamp = it.getString(timeIdx)
                        )
                    )
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error querying pending text logs", e)
        }
        return list
    }

    @Synchronized
    fun deleteTextLogs(ids: List<Long>) {
        if (ids.isEmpty()) return
        try {
            val db = writableDatabase
            val placeholders = ids.joinToString(",") { "?" }
            val args = ids.map { it.toString() }.toTypedArray()
            db.delete(TABLE_TEXT_LOGS, "id IN ($placeholders)", args)
            Log.d(TAG, "Deleted ${ids.size} text log records")
        } catch (e: Exception) {
            Log.e(TAG, "Error deleting text logs", e)
        }
    }

    @Synchronized
    fun getCounts(): Pair<Int, Int> {
        var textCount = 0
        var screenshotCount = 0
        try {
            val db = readableDatabase
            db.rawQuery("SELECT COUNT(*) FROM $TABLE_TEXT_LOGS", null).use {
                if (it.moveToFirst()) textCount = it.getInt(0)
            }
            db.rawQuery("SELECT COUNT(*) FROM $TABLE_SCREENSHOTS", null).use {
                if (it.moveToFirst()) screenshotCount = it.getInt(0)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting counts", e)
        }
        return Pair(textCount, screenshotCount)
    }

    private fun getCurrentIsoTimestamp(): String {
        val sdf = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.getDefault())
        return sdf.format(Date())
    }
}
