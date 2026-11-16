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
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

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

    /**
     * 토큰이 만료되었거나 SDK가 API 오류(apiErrorSubStatus)를 보고했을 때 새 토큰을 받아오는 함수.
     * Flutter 쪽 갱신 로직을 호출하며, 결과는 userId, accessToken, expiresInSeconds를 담은 맵이다.
     */
    @Volatile
    var tokenRefresher: (suspend () -> Map<String, Any?>?)? = null

    private val refreshMutex = Mutex()

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
        refreshIfNeeded(apiErrorSubStatus)
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

    private suspend fun refreshIfNeeded(apiErrorSubStatus: String?) {
        val tokenBefore = currentAccessToken ?: return
        val expiringSoon = currentExpiresTimestamp - EXPIRY_MARGIN_SECONDS <= nowSeconds()
        if (apiErrorSubStatus == null && !expiringSoon) return

        refreshMutex.withLock {
            // 기다리는 동안 다른 호출이 이미 갱신했으면 건너뛴다.
            if (currentAccessToken != tokenBefore) return
            Log.i(TAG, "토큰 재요청 (subStatus=$apiErrorSubStatus, expiringSoon=$expiringSoon)")
            val refreshed = try {
                tokenRefresher?.invoke()
            } catch (e: Exception) {
                Log.w(TAG, "토큰 재요청 실패: ${e.message}")
                null
            }
            val userId = refreshed?.get("userId") as? String
            val accessToken = refreshed?.get("accessToken") as? String
            val expiresIn = (refreshed?.get("expiresInSeconds") as? Number)?.toLong()
            if (userId != null && accessToken != null && expiresIn != null) {
                setUserCredentials(userId, accessToken, expiresIn)
            } else {
                Log.w(TAG, "새 토큰을 받지 못함 - 기존 자격 증명 유지")
            }
        }
    }

    private fun nowSeconds(): Long = System.currentTimeMillis() / 1000

    companion object {
        private const val TAG = "TidalAuth"
        private const val EXPIRY_MARGIN_SECONDS = 60L
        private const val LEGACY_PREFS_NAME = "tidal_native_credentials"
        private val SCOPES = setOf("r_usr", "w_usr", "playback")
    }
}
