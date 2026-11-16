import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import '../../core/utils/app_logger.dart';

class TidalSdkNativeBridge {
  static const MethodChannel _channel = MethodChannel('com.example.tidal_connect_lite/tidal_sdk');
  static const EventChannel _playerEvents = EventChannel('com.example.tidal_connect_lite/player_events');

  static Stream<Map<String, dynamic>>? _playerEventStream;

  /// 네이티브 TIDAL 플레이어 이벤트.
  /// 형식: {type: state|position|transition|ended|error, ...}
  static Stream<Map<String, dynamic>> get playerEvents => _playerEventStream ??= _playerEvents
      .receiveBroadcastStream()
      .map((event) => Map<String, dynamic>.from(event as Map))
      .asBroadcastStream();

  /// Initializes native Tidal SDK Authentication and Player
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

  /// 유료 사용자의 OAuth 토큰(UserId + AccessToken)을 네이티브 TIDAL Player SDK에 주입하여 30초 제한을 해제합니다.
  static Future<bool> updateUserCredentials({
    required String userId,
    required String accessToken,
    required int expiresInSeconds,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map>('updateUserCredentials', {
        'userId': userId,
        'accessToken': accessToken,
        'expiresInSeconds': expiresInSeconds,
      });
      AppLogger.log('TIDAL_NATIVE_SDK', '✅ 네이티브 유료 계정 인증 정보(Level.USER) 동기화 완료: $result', type: LogType.success);
      return true;
    } catch (e) {
      AppLogger.log('TIDAL_NATIVE_SDK', '네이티브 사용자 인증 동기화 실패: $e', type: LogType.error);
      return false;
    }
  }

  /// 네이티브에 남은 사용자 자격 증명을 지운다(로그아웃).
  static Future<void> clearUserCredentials() async {
    try {
      await _channel.invokeMethod('clearUserCredentials');
    } catch (e) {
      AppLogger.log('TIDAL_NATIVE_SDK', '네이티브 자격 증명 삭제 실패: $e', type: LogType.error);
    }
  }

  static Future<Map<String, Object>?> Function()? _tokenRefresher;
  static bool _handlerInstalled = false;

  /// 네이티브 SDK가 토큰 만료·오류로 새 토큰을 요청할 때 호출할 함수를 등록한다.
  ///
  /// 네이티브는 `refreshUserToken`을 호출하고, 반환된 맵(userId, accessToken, expiresInSeconds)이나
  /// null(갱신 불가)을 받는다.
  static void setTokenRefresher(Future<Map<String, Object>?> Function() refresher) {
    _tokenRefresher = refresher;
    _installHandler();
  }

  static void _installHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'refreshUserToken':
          final refresher = _tokenRefresher;
          if (refresher == null) return null;
          return refresher();
        default:
          throw MissingPluginException('Unknown method ${call.method}');
      }
    });
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

  /// Triggers playback via official TIDAL SDK Player (playbackEngine)
  static Future<bool> playTrack({
    required String trackId,
  }) async {
    try {
      AppLogger.log('TIDAL_NATIVE_SDK', 'TIDAL 공식 Player SDK 재생 명령 (trackId: $trackId)', type: LogType.info);
      final result = await _channel.invokeMethod<Map>('playTrack', {
        'trackId': trackId,
      });
      AppLogger.log('TIDAL_NATIVE_SDK', 'TIDAL 공식 Player SDK 재생 응답: $result', type: LogType.success);
      return true;
    } catch (e) {
      AppLogger.log('TIDAL_NATIVE_SDK', 'TIDAL 공식 Player SDK 재생 실패: $e', type: LogType.error);
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
      AppLogger.log('TIDAL_NATIVE_SDK', '일시정지 실패: $e', type: LogType.error);
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
      AppLogger.log('TIDAL_NATIVE_SDK', '재생 재개 실패: $e', type: LogType.error);
      return false;
    }
  }

  /// Seeks to position in milliseconds
  static Future<bool> seekTrack(int positionMs) async {
    try {
      await _channel.invokeMethod('seekTrack', {'positionMs': positionMs});
      return true;
    } catch (e) {
      AppLogger.log('TIDAL_NATIVE_SDK', '탐색 실패: $e', type: LogType.error);
      return false;
    }
  }

  /// Skips to next track via TIDAL SDK
  static Future<bool> skipToNext() async {
    try {
      await _channel.invokeMethod('skipToNext');
      AppLogger.log('TIDAL_NATIVE_SDK', 'TIDAL SDK 다음 곡 명령', type: LogType.info);
      return true;
    } catch (e) {
      AppLogger.log('TIDAL_NATIVE_SDK', 'TIDAL SDK 다음 곡 실패: $e', type: LogType.error);
      return false;
    }
  }

  /// 다음 트랙을 TIDAL SDK 큐에 미리 등록 (TIDAL SDK setNext API)
  static Future<bool> setNextTrack(String trackId) async {
    try {
      await _channel.invokeMethod('setNextTrack', {'trackId': trackId});
      AppLogger.log('TIDAL_NATIVE_SDK', '다음 트랙 등록: $trackId', type: LogType.info);
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

  /// 폰 미디어 볼륨(0~100) 변화. 볼륨 키로 바뀐 경우도 포함한다.
  static Stream<int> get phoneVolumeChanges => playerEvents
      .where((e) => e['type'] == 'phoneVolume')
      .map((e) => (e['percent'] as num).toInt());

  static Future<int?> getPhoneVolume() async {
    try {
      return await _channel.invokeMethod<int>('getPhoneVolume');
    } catch (_) {
      return null;
    }
  }

  static Future<void> setPhoneVolume(int percent) async {
    try {
      await _channel.invokeMethod('setPhoneVolume', {'percent': percent.clamp(0, 100)});
    } catch (_) {}
  }

  /// Android 13 이상에서 재생 알림 권한을 요청한다.
  static Future<void> requestNotificationPermission() async {
    try {
      await _channel.invokeMethod('requestNotificationPermission');
    } catch (_) {}
  }

  /// DLNA 스트리밍 중 Wi-Fi 절전을 막는 WifiLock을 잡거나 놓는다.
  static Future<void> setStreamingLock(bool enabled) async {
    try {
      await _channel.invokeMethod('setStreamingLock', {'enabled': enabled});
    } catch (_) {}
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

  /// 트랙의 스트림 정보(Direct URL 또는 DASH 매니페스트)를 프록시에 등록하고,
  /// 50자 이내의 짧고 표준적인 DLNA 프록시 URL(예: http://192.168.45.63:8765/audio/189569817.mp4)을 반환합니다.
  static Future<String> registerTrackStream({
    required String trackId,
    String directUrl = '',
    String manifestXml = '',
    required String allowedHost,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map>('registerTrackStream', {
        'trackId': trackId,
        'directUrl': directUrl,
        'manifestXml': manifestXml,
        'allowedHost': allowedHost,
      });
      final proxyUrl = result?['proxyUrl']?.toString() ?? '';
      AppLogger.log('TIDAL_NATIVE_SDK', 'DLNA 프록시 등록 완료', type: LogType.success);
      return proxyUrl;
    } catch (e) {
      AppLogger.log('TIDAL_NATIVE_SDK', 'DLNA 프록시 등록 오류: $e', type: LogType.error);
      return '';
    }
  }

  /// 로컬 프록시 서버 상태 조회
  static Future<Map<String, dynamic>> getProxyServerStatus() async {
    try {
      final result = await _channel.invokeMethod<Map>('getProxyServerStatus');
      return {
        'isRunning': result?['isRunning'] ?? false,
        'lanIp': result?['lanIp'] ?? '',
        'port': result?['port'] ?? 8765,
      };
    } catch (e) {
      return {'isRunning': false, 'lanIp': '', 'port': 8765};
    }
  }
}

