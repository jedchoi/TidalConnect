package com.example.tidal_connect_lite

import android.content.Context
import android.util.Log
import com.tidal.sdk.auth.CredentialsProvider
import com.tidal.sdk.auth.model.AuthResult
import com.tidal.sdk.auth.model.Credentials
import com.tidal.sdk.auth.model.success
import com.tidal.sdk.common.TidalMessage
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/**
 * Flutter가 관리하는 사용자 OAuth 토큰을 TIDAL SDK에 공급한다.
 *
 * 토큰은 메모리에만 둔다. 앱을 시작할 때마다 Flutter가 암호화 저장소에서 읽어 다시 주입한다.
 */
class CustomCredentialsProvider(
    context: Context,
    private val clientId: String,
    @Suppress("unused") private val clientSecret: String
) : CredentialsProvider {

    private val _bus = MutableSharedFlow<TidalMessage>()
    override val bus: Flow<TidalMessage> = _bus.asSharedFlow()

    @Volatile
    private var currentAccessToken: String? = null

    @Volatile
    private var currentUserId: String? = null

    @Volatile
    private var currentExpiresTimestamp: Long = 0L

    init {
        // 예전 버전이 토큰을 평문으로 저장하던 파일을 지운다.
        context.deleteSharedPreferences(LEGACY_PREFS_NAME)
    }

    /** Flutter에서 로그인한 사용자의 토큰을 주입한다. */
    fun setUserCredentials(userId: String, accessToken: String, expiresInSeconds: Long) {
        if (userId.isBlank() || accessToken.isBlank()) {
            Log.w(TAG, "빈 사용자 ID 또는 토큰은 무시")
            return
        }
        currentUserId = userId
        currentAccessToken = accessToken
        currentExpiresTimestamp = nowSeconds() + expiresInSeconds
        Log.i(TAG, "사용자 자격 증명 갱신 (UserId: $userId)")
    }

    /** 로그아웃 시 메모리의 사용자 자격 증명을 지운다. */
    fun clearUserCredentials() {
        currentUserId = null
        currentAccessToken = null
        currentExpiresTimestamp = 0L
        Log.i(TAG, "사용자 자격 증명 삭제")
    }

    override suspend fun getCredentials(apiErrorSubStatus: String?): AuthResult<Credentials> {
        val token = currentAccessToken
        val credentials = Credentials(
            clientId = clientId,
            requestedScopes = SCOPES,
            clientUniqueKey = null,
            grantedScopes = SCOPES,
            userId = if (token != null) currentUserId else null,
            expires = if (token != null) currentExpiresTimestamp else null,
            token = token
        )
        Log.i(TAG, "getCredentials -> Level: ${credentials.level}")
        return success(credentials)
    }

    override fun isUserLoggedIn(): Boolean {
        return !currentAccessToken.isNullOrBlank() && !currentUserId.isNullOrBlank()
    }

    private fun nowSeconds(): Long = System.currentTimeMillis() / 1000

    companion object {
        private const val TAG = "TidalAuth"
        private const val LEGACY_PREFS_NAME = "tidal_native_credentials"
        private val SCOPES = setOf("r_usr", "w_usr", "playback")
    }
}
