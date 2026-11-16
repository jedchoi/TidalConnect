package com.example.tidal_connect_lite

import android.content.Context
import android.util.Log
import com.tidal.sdk.auth.CredentialsProvider

class TidalAuthManager(private val context: Context) {
    var customCredentialsProvider: CustomCredentialsProvider? = null
        private set

    val credentialsProvider: CredentialsProvider?
        get() = customCredentialsProvider

    /**
     * 자격 증명 공급자를 만든다. 이미 있으면 그대로 쓴다.
     *
     * 플레이어는 처음 받은 공급자를 계속 들고 있으므로, 여기서 공급자를 새로 만들면
     * 이후 주입하는 사용자 토큰이 플레이어에 전달되지 않는다.
     */
    fun initializeAuth(clientId: String, clientSecret: String): Boolean {
        if (customCredentialsProvider != null) {
            Log.i("TidalAuthManager", "CustomCredentialsProvider 이미 초기화됨 - 재사용")
            return true
        }
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
