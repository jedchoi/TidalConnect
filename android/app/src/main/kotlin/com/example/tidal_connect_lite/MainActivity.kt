package com.example.tidal_connect_lite

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * 화면만 담당한다. 재생 관련 객체는 [PlaybackCore]가 프로세스 범위로 소유하므로
 * Activity가 파괴되어도 재생을 멈추지 않는다.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        PlaybackCore.attach(flutterEngine, this)
    }
}
