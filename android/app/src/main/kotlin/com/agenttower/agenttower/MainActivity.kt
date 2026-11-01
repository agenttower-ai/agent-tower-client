package com.agenttower.agenttower

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    private val alias = "agenttower.connection.v1"
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.agenttower.mobile/project-links")
            .setMethodCallHandler { call, result ->
                if (call.method != "openLink") { result.notImplemented(); return@setMethodCallHandler }
                try {
                    val value = call.arguments as? String ?: error("Expected URL")
                    val uri = Uri.parse(value)
                    val web = uri.scheme == "https" && !uri.host.isNullOrEmpty() && uri.userInfo.isNullOrEmpty()
                    val email = Regex("^mailto:[^\\s@]+@[^\\s@]+$").matches(value)
                    require(web || email)
                    val intent = if (email) Intent(Intent.ACTION_SENDTO, uri) else
                        Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE)
                    startActivity(intent)
                    result.success(null)
                } catch (_: Exception) { result.error("project_link", "Unable to open project link", null) }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.agenttower.mobile/credentials")
            .setMethodCallHandler { call, result ->
                try {
                    val prefs = getSharedPreferences("agenttower_secure", MODE_PRIVATE)
                    when (call.method) {
                        "readLanguage" -> result.success(prefs.getString("language", null))
                        "writeLanguage" -> { check(prefs.edit().putString("language", call.arguments as String).commit()); result.success(null) }
                        "readProjectPreferences" -> result.success(prefs.getString("project_preferences", null))
                        "writeProjectPreferences" -> { check(prefs.edit().putString("project_preferences", call.arguments as String).commit()); result.success(null) }
                        "read" -> {
                            val stored = prefs.getString("connection", null)
                            if (stored == null) result.success(null) else {
                                val parts = stored.split(":")
                                require(parts.size == 2)
                                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                                cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)))
                                result.success(String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), Charsets.UTF_8))
                            }
                        }
                        "write" -> {
                            val value = call.arguments as? String ?: error("Expected string")
                            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                            cipher.init(Cipher.ENCRYPT_MODE, key())
                            val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
                            val stored = Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" + Base64.encodeToString(encrypted, Base64.NO_WRAP)
                            check(prefs.edit().putString("connection", stored).commit())
                            result.success(null)
                        }
                        "clear" -> { check(prefs.edit().remove("connection").commit()); result.success(null) }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) { result.error("secure_storage", "Secure credential storage unavailable", null) }
            }
    }
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
}
