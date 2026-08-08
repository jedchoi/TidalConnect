package com.example.tidal_connect_lite

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.tidal.sdk.auth.*

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.tidal_connect_lite/tidal_sdk"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "initTidalAuth") {
                val clientId = call.argument<String>("clientId") ?: ""
                val clientSecret = call.argument<String>("clientSecret") ?: ""
                try {
                    result.success(mapOf(
                        "status" to "sdk_registered",
                        "clientId" to clientId
                    ))
                } catch (e: Exception) {
                    result.error("INIT_FAILED", e.localizedMessage, e.toString())
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
