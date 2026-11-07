package com.example.attorlink_flutter

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileNotFoundException
import java.security.KeyStore
import java.security.MessageDigest
import java.security.UnrecoverableKeyException
import java.util.concurrent.Executors
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Platform-only storage: no tokens in preferences, backups, logs, or error text. */
class SecureSessionBridge(context: Context, messenger: BinaryMessenger) {
    private val directory = context.applicationContext.noBackupFilesDir
    private val channel = MethodChannel(messenger, "attorlink/secure-session")
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var closed = false

    init {
        channel.setMethodCallHandler { call, result ->
            val origin = call.argument<String>("origin")
            val value = call.argument<String>("value")
            if (origin.isNullOrBlank() || origin.length > 4096 ||
                (call.method == "write" && (value.isNullOrEmpty() || value.length > 65536))) {
                result.error("INVALID_ARGUMENT", "Invalid secure storage request.", null)
            } else if (call.method !in setOf("read", "write", "clear")) {
                result.notImplemented()
            } else {
                worker.execute {
                    try {
                        val scope = MessageDigest.getInstance("SHA-256")
                            .digest(origin.toByteArray(Charsets.UTF_8))
                            .joinToString("") { "%02x".format(it.toInt() and 0xff) }
                        val alias = "attorlink.session.$scope"
                        val file = AtomicFile(File(directory, "session-$scope.bin"))
                        val output = when (call.method) {
                            "read" -> read(file, alias, origin)
                            "write" -> { write(file, alias, origin, value!!); null }
                            else -> { clear(file, alias); null }
                        }
                        main.post { if (!closed) result.success(output) }
                    } catch (_: InvalidSession) {
                        main.post { if (!closed) result.error("INVALID_SESSION", "Saved session is invalid.", null) }
                    } catch (_: Exception) {
                        main.post { if (!closed) result.error("STORE_UNAVAILABLE", "Secure session storage unavailable.", null) }
                    }
                }
            }
        }
    }

    private fun keyStore() = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    private fun key(alias: String, create: Boolean): SecretKey? {
        val store = keyStore()
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        if (!create) return null
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setRandomizedEncryptionRequired(true)
                .build())
        }.generateKey()
    }

    private fun read(file: AtomicFile, alias: String, origin: String): String? {
        val bytes = try {
            file.openRead().use { input ->
                val output = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(4096)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (output.size() + count > 131072) throw InvalidSession()
                    output.write(buffer, 0, count)
                }
                output.toByteArray()
            }
        } catch (_: FileNotFoundException) { return null }
        try {
            if (bytes.size < 29 || bytes[0].toInt() != 1) throw InvalidSession()
            val savedKey = key(alias, false) ?: throw InvalidSession()
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, savedKey, GCMParameterSpec(128, bytes.copyOfRange(1, 13)))
            cipher.updateAAD(origin.toByteArray(Charsets.UTF_8))
            return String(cipher.doFinal(bytes.copyOfRange(13, bytes.size)), Charsets.UTF_8)
        } catch (_: AEADBadTagException) {
            clear(file, alias); throw InvalidSession()
        } catch (_: KeyPermanentlyInvalidatedException) {
            clear(file, alias); throw InvalidSession()
        } catch (_: UnrecoverableKeyException) {
            clear(file, alias); throw InvalidSession()
        } catch (_: InvalidSession) {
            clear(file, alias); throw InvalidSession()
        }
    }

    private fun write(file: AtomicFile, alias: String, origin: String, value: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key(alias, true)!!)
        cipher.updateAAD(origin.toByteArray(Charsets.UTF_8))
        val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        check(cipher.iv.size == 12)
        val output = file.startWrite()
        try {
            output.write(byteArrayOf(1))
            output.write(cipher.iv)
            output.write(encrypted)
            file.finishWrite(output)
        } catch (error: Exception) {
            file.failWrite(output)
            throw error
        }
    }

    private fun clear(file: AtomicFile, alias: String) {
        // Deleting the key also makes a surviving/unreadable ciphertext unusable.
        keyStore().deleteEntry(alias)
        file.delete()
    }

    fun close() { closed = true; channel.setMethodCallHandler(null) }
    private class InvalidSession : Exception()
    companion object {
        // Also serializes operations across Activity recreation/Flutter engines.
        private val worker = Executors.newSingleThreadExecutor()
    }
}
