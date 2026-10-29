package jp.kakeibo.share.data

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.github.jan.supabase.auth.SessionManager
import io.github.jan.supabase.auth.exception.NoSessionFoundException
import io.github.jan.supabase.auth.user.UserSession
import kotlinx.serialization.json.Json
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

// ログインのセッション（アクセストークン・更新トークン）を、Android Keystore の鍵（端末の外に出ない）で AES-GCM 暗号化して保存する。
// supabase-kt の標準（暗号化しない設定ファイル）の代わり。バックアップと端末移行からは除外（data_extraction_rules.xml）
class SecureSessionManager(context: Context) : SessionManager {
    private val prefs = context.getSharedPreferences("kakeibo_session", Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true }

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getEntry(ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).setKeySize(256).build())
        return gen.generateKey()
    }

    override suspend fun saveSession(session: UserSession) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        val enc = cipher.doFinal(json.encodeToString(UserSession.serializer(), session).toByteArray())
        prefs.edit().putString("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP)).putString("data", Base64.encodeToString(enc, Base64.NO_WRAP)).apply()
    }

    // 保存がなければ例外（ライブラリの loadSessionOrNull が null にする）
    override suspend fun loadSession(): UserSession {
        val iv = prefs.getString("iv", null) ?: throw NoSessionFoundException()
        val data = prefs.getString("data", null) ?: throw NoSessionFoundException()
        return try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, Base64.decode(iv, Base64.NO_WRAP))) }
            json.decodeFromString(UserSession.serializer(), String(cipher.doFinal(Base64.decode(data, Base64.NO_WRAP))))
        } catch (e: Exception) {
            deleteSession()   // 鍵が変わった・壊れた → 捨ててログインし直してもらう
            throw e
        }
    }

    override suspend fun deleteSession() {
        prefs.edit().clear().apply()
    }

    private companion object { const val ALIAS = "kakeibo_session_key" }
}
