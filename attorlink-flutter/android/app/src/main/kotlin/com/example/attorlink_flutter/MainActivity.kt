package com.example.attorlink_flutter

import android.app.Activity
import android.content.Intent
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private var secureSession: SecureSessionBridge? = null
    private var boostPlatform: BoostPlatformBridge? = null
    private var photoResult: MethodChannel.Result? = null
    private val photoRequest = 7341
    private var selectionLimit = 5 * 1024 * 1024

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        secureSession?.close()
        secureSession = SecureSessionBridge(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        boostPlatform?.close()
        boostPlatform = BoostPlatformBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "attorlink/client-photo")
            .setMethodCallHandler { call, result ->
                if (call.method != "pickPhoto") {
                    result.notImplemented()
                } else if (photoResult != null) {
                    result.error("BUSY", "A photo selection is already open.", null)
                } else {
                    photoResult = result
                    val document = call.argument<Boolean>("document") == true
                    selectionLimit = (if (document) 10 else 5) * 1024 * 1024
                    try {
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = if (document) "*/*" else "image/*"
                            putExtra(Intent.EXTRA_MIME_TYPES, if (document)
                                arrayOf("application/pdf", "image/jpeg", "image/png")
                                else arrayOf("image/jpeg", "image/png", "image/webp"))
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        @Suppress("DEPRECATION")
                        startActivityForResult(intent, photoRequest)
                    } catch (_: Exception) {
                        photoResult = null
                        result.error("UNAVAILABLE", "The document picker is unavailable.", null)
                    }
                }
            }
    }

    @Deprecated("Uses the platform document picker without additional libraries")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (boostPlatform?.onActivityResult(requestCode, resultCode, data) == true) return
        if (requestCode != photoRequest) return
        val result = photoResult ?: return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            photoResult = null
            result.success(null)
            return
        }
        val limit = selectionLimit
        Thread {
            try {
                var name = "photo"
                // Some providers expose readable content but no display-name
                // metadata. Its absence must not prevent a valid file upload.
                try {
                    contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) name = cursor.getString(0) ?: name
                    }
                } catch (_: Exception) {
                    // The stream read below is the authoritative access check.
                }
                val bytes = ByteArrayOutputStream()
                contentResolver.openInputStream(uri)?.use { input ->
                    val buffer = ByteArray(8192)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        if (bytes.size() + count > limit) throw IllegalArgumentException("SIZE")
                        bytes.write(buffer, 0, count)
                    }
                } ?: throw IllegalStateException("READ")
                val photo = mapOf("name" to name, "bytes" to bytes.toByteArray())
                runOnUiThread {
                    if (photoResult === result) {
                        photoResult = null
                        result.success(photo)
                    }
                }
            } catch (error: Exception) {
                val message = if (error is IllegalArgumentException) "Choose a file of at most ${limit / (1024 * 1024)} MB."
                    else "The selected photo could not be read."
                runOnUiThread {
                    if (photoResult === result) {
                        photoResult = null
                        result.error("PHOTO_READ", message, null)
                    }
                }
            }
        }.start()
    }

    override fun onDestroy() {
        boostPlatform?.close()
        boostPlatform = null
        secureSession?.close()
        secureSession = null
        photoResult?.error("CANCELLED", "Photo selection was cancelled.", null)
        photoResult = null
        super.onDestroy()
    }
}
