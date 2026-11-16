package com.example.tidal_connect_lite

import android.content.Context
import android.util.Log
import com.tidal.sdk.auth.CredentialsProvider

class TidalAuthManager(private val context: Context) {
    var customCredentialsProvider: CustomCredentialsProvider? = null
        private set

    val credentialsProvider: CredentialsProvider?
        get() = customCredentialsProvider

    fun initializeAuth(clientId: String, clientSecret: String): Boolean {
        return try {
            customCredentialsProvider = CustomCredentialsProvider(context, clientId, clientSecret)
            Log.i("TidalAuthManager", "CustomCredentialsProvider 초기화 성공")
            true
        } catch (e: Exception) {
            Log.e("TidalAuthManager", "CustomCredentialsProvider 초기화 실패: ${e.message}", e)
            false
        }
    }

    fun updateUserCredentials(userId: String, accessToken: String, expiresInSeconds: Long = 86400L * 30) {
        customCredentialsProvider?.setUserCredentials(userId, accessToken, expiresInSeconds)
        Log.i("TidalAuthManager", "사용자 인증 정보 업데이트 완료 (UserId: $userId)")
    }

    suspend fun authenticateUser(): Boolean {
        val creds = customCredentialsProvider?.getCredentials()
        return creds != null && creds.isSuccess
    }

    fun isUserLoggedIn(): Boolean {
        return customCredentialsProvider?.isUserLoggedIn() ?: false
    }
}
