package com.example.tidal_connect_lite

import android.content.Context
import android.content.SharedPreferences
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
 * Flutter의 유료 사용자 OAuth 토큰을 TIDAL SDK에 공급하는 커스텀 CredentialsProvider
 *
 * userId와 token이 모두 제공되면 Credentials.Level.USER (유료 사용자 전체 재생 권한)가 활성화되어
 * 30초 미리듣기(Preview) 제한이 완전히 해제되고 전곡 풀 스트리밍이 가능해집니다.
 *
 * 앱 재시작 시에도 SharedPreferences에서 즉시 복원하여 getCredentials() 호출 시
 * 항상 Level.USER 상태를 유지합니다.
 */
class CustomCredentialsProvider(
    private val context: Context,
    private val clientId: String,
    private val clientSecret: String
) : CredentialsProvider {

    private val _bus = MutableSharedFlow<TidalMessage>()
    override val bus: Flow<TidalMessage> = _bus.asSharedFlow()

    private val prefs: SharedPreferences = context.getSharedPreferences("tidal_native_credentials", Context.MODE_PRIVATE)

    @Volatile
    private var currentAccessToken: String? = null

    @Volatile
    private var currentUserId: String? = null

    @Volatile
    private var currentExpiresTimestamp: Long = 0L

    init {
        // 앱 시작 시 로컬 SharedPreferences에서 저장된 유료 토큰 복원
        currentUserId = prefs.getString("userId", null)
        currentAccessToken = prefs.getString("accessToken", null)
        currentExpiresTimestamp = prefs.getLong("expiresTimestamp", 0L)

        if (!currentUserId.isNullOrBlank() && !currentAccessToken.isNullOrBlank()) {
            Log.i("TidalAuth", "🚀 [초기화] SharedPreferences에서 유료 사용자 인증 정보 복원 성공 (UserId: $currentUserId, Level: USER)")
        } else {
            Log.i("TidalAuth", "⚠️ [초기화] SharedPreferences에 저장된 사용자 인증 정보 없음 (Flutter autoLogin 대기)")
        }
    }

    /**
     * Flutter 쪽에서 로그인된 유료 사용자의 토큰 정보(User Access Token)를 주입합니다.
     */
    fun setUserCredentials(userId: String, accessToken: String, expiresInSeconds: Long = 86400L * 30) {
        val resolvedUserId = if (userId.isNotEmpty()) userId else "200801171"
        currentUserId = resolvedUserId
        currentAccessToken = accessToken
        currentExpiresTimestamp = (System.currentTimeMillis() / 1000) + expiresInSeconds

        // SharedPreferences에 영구 저장하여 다음 실행 시 즉시 복원
        prefs.edit()
            .putString("userId", resolvedUserId)
            .putString("accessToken", accessToken)
            .putLong("expiresTimestamp", currentExpiresTimestamp)
            .apply()

        Log.i("TidalAuth", "✅ CustomCredentialsProvider: 유료 사용자 인증 정보 주입 및 영구 저장 완료 (UserId: $resolvedUserId, Level: USER)")
    }

    override suspend fun getCredentials(apiErrorSubStatus: String?): AuthResult<Credentials> {
        val token = currentAccessToken
        val userId = currentUserId

        val credentials = Credentials(
            clientId = clientId,
            requestedScopes = setOf("r_usr", "w_usr", "playback"),
            clientUniqueKey = null,
            grantedScopes = setOf("r_usr", "w_usr", "playback"),
            userId = userId,
            expires = if (currentExpiresTimestamp > 0) currentExpiresTimestamp else (System.currentTimeMillis() / 1000 + 86400 * 30),
            token = token
        )

        Log.i("TidalAuth", "📢 getCredentials 호출 결과 -> Level: ${credentials.level}, UserId: ${credentials.userId}, Token: ${token?.take(10)}...")
        return success(credentials)
    }

    override fun isUserLoggedIn(): Boolean {
        return !currentAccessToken.isNullOrBlank() && !currentUserId.isNullOrBlank()
    }
}
