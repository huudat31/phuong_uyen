package com.example.phuonguyen

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.util.Log
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class DbHelper(context: Context) : SQLiteOpenHelper(context, DATABASE_NAME, null, DATABASE_VERSION) {

    companion object {
        private const val TAG = "SelfMonitorDb"
        const val DATABASE_NAME = "self_monitor.db"
        const val DATABASE_VERSION = 1
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
        Log.d(TAG, "Created SQLite tables in $DATABASE_NAME")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // Upgrade logic if schema changes
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

    private fun getCurrentIsoTimestamp(): String {
        val sdf = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.getDefault())
        return sdf.format(Date())
    }
}
