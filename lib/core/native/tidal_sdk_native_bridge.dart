import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import '../../core/utils/app_logger.dart';

class TidalSdkNativeBridge {
  static const MethodChannel _channel = MethodChannel('com.example.tidal_connect_lite/tidal_sdk');

  /// Initializes native Tidal SDK Authentication
  static Future<bool> initTidalAuth({
    required String clientId,
    required String clientSecret,
  }) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      AppLogger.log('TIDAL_NATIVE_SDK', '안드로이드 네이티브 KeepCreatedCredentialsProvider 초기화 (ClientID: $clientId)', type: LogType.network);
      final result = await _channel.invokeMethod<Map>('initTidalAuth', {
        'clientId': clientId,
        'clientSecret': clientSecret,
      });
      AppLogger.log('TIDAL_NATIVE_SDK', '네이티브 KeepCreatedCredentialsProvider 생성 성공: $result', type: LogType.success);
      return true;
    } catch (e) {
      AppLogger.log('TIDAL_NATIVE_SDK', '네이티브 KeepCreatedCredentialsProvider 초기화 오류: $e', type: LogType.error);
      return false;
    }
  }

  /// Triggers authentication via native CredentialsProvider
  static Future<bool> authenticateUser() async {
    try {
      final result = await _channel.invokeMethod<Map>('authenticateUser');
      AppLogger.log('TIDAL_NATIVE_SDK', '네이티브 CredentialsProvider 인증 상태: $result', type: LogType.info);
      return result?['status'] == 'authenticated';
    } catch (e) {
      AppLogger.log('TIDAL_NATIVE_SDK', '네이티브 인증 실행 예외: $e', type: LogType.error);
      return false;
    }
  }

  /// Triggers playback via native Android MediaPlayer or Tidal SDK Player
  static Future<bool> playTrack({
    required String trackId,
    String streamUrl = '',
  }) async {
    try {
      AppLogger.log('TIDAL_NATIVE_SDK', '스마트폰 스피커 오디오 재생 명령 (trackId: $trackId, streamUrl: $streamUrl)', type: LogType.info);
      final result = await _channel.invokeMethod<Map>('playTrack', {
        'trackId': trackId,
        'streamUrl': streamUrl,
      });
      AppLogger.log('TIDAL_NATIVE_SDK', '스마트폰 스피커 재생 응답: $result', type: LogType.success);
      return true;
    } catch (e) {
      AppLogger.log('TIDAL_NATIVE_SDK', '스마트폰 스피커 재생 실패: $e', type: LogType.error);
      return false;
    }
  }

  /// Pauses playback
  static Future<bool> pauseTrack() async {
    try {
      await _channel.invokeMethod('pauseTrack');
      AppLogger.log('TIDAL_NATIVE_SDK', '스마트폰 스피커 일시정지 완료', type: LogType.info);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Resumes playback
  static Future<bool> resumeTrack() async {
    try {
      await _channel.invokeMethod('resumeTrack');
      AppLogger.log('TIDAL_NATIVE_SDK', '스마트폰 스피커 재생 재개 완료', type: LogType.info);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Seeks to position in milliseconds
  static Future<bool> seekTrack(int positionMs) async {
    try {
      await _channel.invokeMethod('seekTrack', {'positionMs': positionMs});
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Stops playback via native Tidal SDK player
  static Future<bool> stopTrack() async {
    try {
      await _channel.invokeMethod('stopTrack');
      AppLogger.log('TIDAL_NATIVE_SDK', '네이티브 Player stop 완료', type: LogType.info);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Releases native Tidal SDK Player
  static Future<bool> releasePlayer() async {
    try {
      await _channel.invokeMethod('releasePlayer');
      AppLogger.log('TIDAL_NATIVE_SDK', '네이티브 Player release 완료', type: LogType.info);
      return true;
    } catch (e) {
      return false;
    }
  }
}
