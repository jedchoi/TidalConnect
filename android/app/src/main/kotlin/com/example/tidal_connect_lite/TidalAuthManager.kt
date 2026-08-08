package com.example.tidal_connect_lite

import android.content.Context
import com.tidal.sdk.auth.TidalAuth
import com.tidal.sdk.auth.CredentialsProvider
import com.tidal.sdk.auth.model.AuthConfig

class TidalAuthManager(private val context: Context) {
    var credentialsProvider: CredentialsProvider? = null
        private set

    fun initializeAuth(clientId: String, clientSecret: String): Boolean {
        return try {
            val authConfig = AuthConfig(
                clientId = clientId,
                clientSecret = clientSecret,
                credentialsKey = "tidal_storage"
            )
            val tidalAuth = TidalAuth.getInstance(authConfig, context)
            credentialsProvider = tidalAuth.credentialsProvider
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    suspend fun authenticateUser(): Boolean {
        return try {
            val credentials = credentialsProvider?.getCredentials()
            credentials != null && credentials.isSuccess
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }
}
