package com.example.tidal_connect_lite

import android.content.Context
import com.tidal.sdk.auth.KeepCreatedCredentialsProvider
import com.tidal.sdk.auth.CredentialsProvider

class TidalAuthManager(private val context: Context) {
    var credentialsProvider: CredentialsProvider? = null
        private set

    fun initializeAuth(clientId: String, clientSecret: String): Boolean {
        return try {
            credentialsProvider = KeepCreatedCredentialsProvider(
                context = context,
                clientId = clientId
            )
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
