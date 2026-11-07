package com.example.attorlink_flutter

import android.app.Activity
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** SDK-only browser handoff and user-selected document export. No storage permission. */
class BoostPlatformBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "attorlink/boost-platform")
    private val saveRequest = 7342
    private var pending: MethodChannel.Result? = null
    private var selectedDestination: Uri? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "openCheckout" -> {
                    try {
                        val uri = Uri.parse(call.argument<String>("url") ?: "")
                        require(uri.scheme == "https" && !uri.host.isNullOrBlank() && uri.userInfo == null)
                        activity.startActivity(Intent(Intent.ACTION_VIEW, uri).apply {
                            addCategory(Intent.CATEGORY_BROWSABLE)
                        })
                        result.success(null)
                    } catch (_: Exception) {
                        result.error("UNAVAILABLE", "No browser could open this checkout URL.", null)
                    }
                }
                "chooseInvoice" -> {
                    if (pending != null) {
                        result.error("BUSY", "An invoice export is already pending.", null)
                    } else {
                        try {
                            val filename = call.argument<String>("filename") ?: "invoice.pdf"
                            require(filename.matches(Regex("[A-Za-z0-9._-]+\\.pdf")))
                            pending = result
                            selectedDestination = null
                            @Suppress("DEPRECATION")
                            activity.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "application/pdf"
                                putExtra(Intent.EXTRA_TITLE, filename)
                            }, saveRequest)
                        } catch (_: Exception) {
                            pending = null
                            selectedDestination = null
                            result.error("UNAVAILABLE", "The invoice document picker is unavailable.", null)
                        }
                    }
                }
                "writeInvoice" -> {
                    if (pending != null) {
                        result.error("BUSY", "An invoice export is already pending.", null)
                    } else {
                        val uri = selectedDestination
                        selectedDestination = null
                        val bytes = call.argument<ByteArray>("bytes")
                        if (uri == null || uri.toString() != call.argument<String>("destination") ||
                            bytes == null || bytes.size < 5 ||
                            String(bytes.copyOfRange(0, 5), Charsets.US_ASCII) != "%PDF-") {
                            result.error("INVALID", "Select an invoice destination first.", null)
                        } else {
                            pending = result
                            writeInvoice(uri, bytes, result)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != saveRequest) return false
        val result = pending ?: return true
        val uri = data?.data
        pending = null
        if (resultCode != Activity.RESULT_OK || uri == null) {
            selectedDestination = null
            result.success(null)
        } else {
            selectedDestination = uri
            result.success(uri.toString())
        }
        return true
    }

    private fun writeInvoice(uri: Uri, bytes: ByteArray, result: MethodChannel.Result) {
        Thread {
            var success = false
            try {
                activity.contentResolver.openOutputStream(uri, "w")?.use { output ->
                    output.write(bytes)
                    output.flush()
                    success = true
                }
            } catch (_: Exception) {
                // No paths, credentials or provider errors are logged or sent to Dart.
            }
            activity.runOnUiThread {
                if (pending === result) {
                    pending = null
                    if (success) result.success(true)
                    else result.error("WRITE", "Unable to save invoice PDF.", null)
                }
            }
        }.start()
    }

    fun close() {
        channel.setMethodCallHandler(null)
        pending?.error("CANCELLED", "Invoice export was interrupted.", null)
        pending = null
        selectedDestination = null
    }
}
