import 'package:flutter/services.dart';
import '../../core/utils/app_logger.dart';

class TidalSdkNativeBridge {
  static const MethodChannel _channel = MethodChannel('com.example.tidal_connect_lite/tidal_sdk');

  /// Initializes native Tidal SDK Authentication (com.tidal.sdk.auth)
  static Future<bool> initTidalAuth({
    required String clientId,
    required String clientSecret,
  }) async {
    try {
      AppLogger.log('TIDAL_NATIVE_SDK', '안드로이드 네이티브 com.tidal.sdk.auth 인증 모듈 초기화 시도 (ClientID: $clientId)', type: LogType.network);
      final result = await _channel.invokeMethod<Map>('initTidalAuth', {
        'clientId': clientId,
        'clientSecret': clientSecret,
      });
      AppLogger.log('TIDAL_NATIVE_SDK', '네이티브 TIDAL SDK 인증 모듈 초기화 성공: $result', type: LogType.success);
      return true;
    } catch (e) {
      AppLogger.log('TIDAL_NATIVE_SDK', '네이티브 TIDAL SDK 인증 모듈 초기화 실패: $e', type: LogType.error);
      return false;
    }
  }

  /// Triggers playback via native Tidal SDK player engine (com.tidal.sdk.player)
  static Future<bool> playTrack({
    required String trackId,
    required String streamUrl,
  }) async {
    try {
      AppLogger.log('TIDAL_NATIVE_SDK', '네이티브 com.tidal.sdk.player 음원 재생 요청 (TrackID: $trackId)', type: LogType.info);
      final result = await _channel.invokeMethod<Map>('playTrack', {
        'trackId': trackId,
        'streamUrl': streamUrl,
      });
      AppLogger.log('TIDAL_NATIVE_SDK', '네이티브 재생 상태: $result', type: LogType.success);
      return true;
    } catch (e) {
      AppLogger.log('TIDAL_NATIVE_SDK', '네이티브 음원 재생 중 오류: $e', type: LogType.error);
      return false;
    }
  }

  /// Pauses playback via native Tidal SDK player
  static Future<bool> pauseTrack() async {
    try {
      await _channel.invokeMethod('pauseTrack');
      AppLogger.log('TIDAL_NATIVE_SDK', '네이티브 일시정지 완료', type: LogType.info);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Resumes playback via native Tidal SDK player
  static Future<bool> resumeTrack() async {
    try {
      await _channel.invokeMethod('resumeTrack');
      AppLogger.log('TIDAL_NATIVE_SDK', '네이티브 재생 재개 완료', type: LogType.info);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Seeks playback position via native Tidal SDK player
  static Future<bool> seekTrack(int positionMs) async {
    try {
      await _channel.invokeMethod('seekTrack', {'positionMs': positionMs});
      return true;
    } catch (e) {
      return false;
    }
  }
}
