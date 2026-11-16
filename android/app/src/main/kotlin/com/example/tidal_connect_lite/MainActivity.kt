package com.example.tidal_connect_lite

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * 화면만 담당한다. audio_service가 Flutter 엔진을 캐시하므로 Activity가 사라져도 Dart 쪽 재생 로직이 살아 있다. 재생 관련 객체는 [PlaybackCore]가 프로세스 범위로 소유하므로
 * Activity가 파괴되어도 재생을 멈추지 않는다.
 */
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        PlaybackCore.attach(flutterEngine, this)
    }
}
