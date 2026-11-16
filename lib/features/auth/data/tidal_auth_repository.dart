import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../core/config/tidal_config.dart';
import '../../../core/native/tidal_sdk_native_bridge.dart';
import '../../../core/utils/app_logger.dart';
import '../domain/models/auth_token.dart';
import 'secure_storage_service.dart';

/// 네이티브 TIDAL SDK로 사용자 자격 증명을 전달하는 통로.
///
/// 테스트에서는 가짜 구현으로 바꿔 끼울 수 있도록 분리했다.
abstract class NativeCredentialsSink {
  Future<bool> initialize();
  Future<void> setUserCredentials({required String userId, required String accessToken, required int expiresInSeconds});
  Future<void> clearUserCredentials();
  void setTokenRefresher(Future<Map<String, Object>?> Function() refresher);
}

class _BridgeCredentialsSink implements NativeCredentialsSink {
  const _BridgeCredentialsSink();

  @override
  Future<bool> initialize() => TidalSdkNativeBridge.initTidalAuth(
        clientId: TidalConfig.clientId,
        clientSecret: TidalConfig.clientSecret,
      );

  @override
  Future<void> setUserCredentials({required String userId, required String accessToken, required int expiresInSeconds}) =>
      TidalSdkNativeBridge.updateUserCredentials(
        userId: userId,
        accessToken: accessToken,
        expiresInSeconds: expiresInSeconds,
      );

  @override
  Future<void> clearUserCredentials() => TidalSdkNativeBridge.clearUserCredentials();

  @override
  void setTokenRefresher(Future<Map<String, Object>?> Function() refresher) =>
      TidalSdkNativeBridge.setTokenRefresher(refresher);
}

/// 사용자 토큰 갱신 결과.
enum RefreshOutcome { success, rejected, temporaryFailure }

/// TIDAL 인증 상태의 단일 출처.
///
/// 앱 전체에서 하나의 인스턴스만 쓴다(`authRepositoryProvider`).
/// - 사용자 토큰: 로그인한 계정의 토큰. 네이티브 플레이어에도 전달된다.
/// - 앱 토큰: 비로그인 상태에서 목록·검색에 쓰는 client credentials 토큰. 네이티브로 보내지 않는다.
class TidalAuthRepository {
  final SecureStorageService _storageService;
  final Dio _dio;
  final NativeCredentialsSink _native;

  /// 현재 로그인한 사용자 토큰. null이면 로그아웃 상태.
  final ValueNotifier<AuthToken?> userToken = ValueNotifier<AuthToken?>(null);

  AuthToken? _clientToken;
  bool _loaded = false;
  bool _nativeInitialized = false;
  Future<RefreshOutcome>? _refreshInFlight;
  Future<AuthToken?>? _clientTokenInFlight;

  TidalAuthRepository({SecureStorageService? storageService, Dio? dio, NativeCredentialsSink? nativeSink})
      : _storageService = storageService ?? SecureStorageService(),
        _native = nativeSink ?? const _BridgeCredentialsSink(),
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 15),
              ),
            );

  AuthToken? get currentToken => userToken.value;
  bool get isLoggedIn => userToken.value != null;

  /// 네이티브 SDK를 초기화한다. 앱 시작 시 `main()`에서 한 번만 호출한다.
  Future<void> initNativeSdk() async {
    if (_nativeInitialized) return;
    _nativeInitialized = true;
    _native.setTokenRefresher(_provideTokenToNative);
    await _native.initialize();
  }

  /// 저장된 사용자 토큰을 복원하고, 만료되었으면 갱신한다.
  ///
  /// 사용할 수 있는 사용자 토큰을 반환한다. 네트워크 오류로 갱신하지 못하면 null을 반환하지만
  /// 로그인 상태([userToken])는 유지한다.
  Future<AuthToken?> autoLogin() => getValidUserToken();

  Future<AuthToken?> getValidUserToken() async {
    await _ensureLoaded();
    final token = userToken.value;
    if (token == null) return null;
    if (!token.isExpired) return token;

    AppLogger.log('TIDAL_AUTH', '사용자 토큰 만료 임박 -> 갱신 시도', type: LogType.warning);
    final outcome = await _refreshUserToken();
    if (outcome == RefreshOutcome.success) return userToken.value;
    return null;
  }

  /// 목록·검색 같은 공개 카탈로그 API용 토큰.
  /// 사용자 토큰이 있으면 그것을, 없으면 앱 토큰을 쓴다.
  Future<String?> getCatalogToken() async {
    final user = await getValidUserToken();
    if (user != null) return user.accessToken;
    if (isLoggedIn) {
      AppLogger.log('TIDAL_AUTH', '사용자 토큰 일시 사용 불가 -> 앱 토큰으로 조회', type: LogType.warning);
    }
    final client = await _getClientToken();
    return client?.accessToken;
  }

  /// API가 401을 돌려줬을 때 새 토큰을 받는다. 로그인 상태면 사용자 토큰을 갱신하고,
  /// 아니면 앱 토큰을 새로 발급받는다. 실패하면 null.
  Future<String?> recoverFromUnauthorized() async {
    await _ensureLoaded();
    if (userToken.value != null) {
      final outcome = await _refreshUserToken();
      return outcome == RefreshOutcome.success ? userToken.value?.accessToken : null;
    }
    _clientToken = null;
    await _storageService.deleteClientToken();
    return (await _getClientToken())?.accessToken;
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    await _storageService.migrateLegacyToken();
    _clientToken = await _storageService.getClientToken();
    final stored = await _storageService.getUserToken();
    if (stored == null) {
      AppLogger.log('TIDAL_AUTH', '저장된 사용자 토큰 없음 (로그인 필요)', type: LogType.warning);
      return;
    }
    userToken.value = stored;
    if (!stored.isExpired) {
      AppLogger.log('TIDAL_AUTH', '저장된 사용자 토큰 복원 (UserId: ${stored.userId})', type: LogType.success);
      await _pushToNative(stored);
    }
  }

  // ──────────────────────────────────────────────
  // 앱 토큰 (client credentials)
  // ──────────────────────────────────────────────

  Future<AuthToken?> _getClientToken() async {
    final cached = _clientToken;
    if (cached != null && !cached.isExpired) return cached;
    return _clientTokenInFlight ??= authenticateClientCredentials().whenComplete(() => _clientTokenInFlight = null);
  }

  /// 앱 단위 토큰을 발급받는다. 사용자 토큰과 별도로 저장하며 네이티브로 보내지 않는다.
  Future<AuthToken?> authenticateClientCredentials() async {
    final url = '${TidalConfig.authBaseUrl}/token';
    AppLogger.log('TIDAL_AUTH', 'POST $url (grant_type=client_credentials)', type: LogType.network);
    try {
      final response = await _dio.post(
        url,
        data: {'grant_type': 'client_credentials'},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'Authorization': 'Basic ${_basicAuth()}'},
        ),
      );
      final data = response.data;
      final token = AuthToken(
        accessToken: data['access_token'] as String,
        refreshToken: '',
        expiresAt: DateTime.now().add(Duration(seconds: (data['expires_in'] as num?)?.toInt() ?? 604800)),
      );
      _clientToken = token;
      await _storageService.saveClientToken(token);
      AppLogger.log('TIDAL_AUTH', '앱 토큰 발급 성공 [HTTP ${response.statusCode}]', type: LogType.success);
      return token;
    } catch (e) {
      _logError('앱 토큰 발급 실패', e);
      return null;
    }
  }

  // ──────────────────────────────────────────────
  // 사용자 로그인 (PKCE)
  // ──────────────────────────────────────────────

  /// PKCE 인증 코드를 사용자 토큰으로 교환한다. userId를 얻지 못하면 로그인 실패로 처리한다.
  Future<AuthToken?> exchangeAuthorizationCode({
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) async {
    final url = '${TidalConfig.authBaseUrl}/token';
    AppLogger.log('TIDAL_AUTH', 'POST $url (authorization_code 교환)', type: LogType.network);
    try {
      final response = await _dio.post(
        url,
        data: {
          'client_id': TidalConfig.clientId,
          'grant_type': 'authorization_code',
          'code': code,
          'code_verifier': codeVerifier,
          'redirect_uri': redirectUri,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'Authorization': 'Basic ${_basicAuth()}'},
        ),
      );

      final data = response.data;
      final accessToken = data['access_token'] as String;
      var userId = '';
      if (data['user'] is Map && data['user']['userId'] != null) {
        userId = data['user']['userId'].toString();
      } else if (data['user_id'] != null) {
        userId = data['user_id'].toString();
      }
      if (userId.isEmpty) {
        userId = await _fetchUserIdFromSession(accessToken);
      }
      if (userId.isEmpty) {
        AppLogger.log('TIDAL_AUTH', '사용자 ID를 확인할 수 없어 로그인 실패 처리', type: LogType.error);
        return null;
      }

      final token = AuthToken(
        accessToken: accessToken,
        refreshToken: data['refresh_token'] as String? ?? '',
        expiresAt: DateTime.now().add(Duration(seconds: (data['expires_in'] as num?)?.toInt() ?? 86400)),
        userId: userId,
      );
      await _setUserToken(token);
      AppLogger.log('TIDAL_AUTH', '사용자 로그인 성공 (UserId: $userId)', type: LogType.success);
      return token;
    } catch (e) {
      _logError('인증 코드 교환 실패', e);
      return null;
    }
  }

  Future<String> _fetchUserIdFromSession(String accessToken) async {
    try {
      final response = await _dio.get(
        '${TidalConfig.apiBaseUrl}/sessions',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final data = response.data;
      return data['userId']?.toString() ?? data['user']?['userId']?.toString() ?? '';
    } catch (e) {
      _logError('세션 조회 실패', e);
      return '';
    }
  }

  // ──────────────────────────────────────────────
  // 갱신
  // ──────────────────────────────────────────────

  /// 사용자 토큰을 갱신한다. 동시에 여러 곳에서 호출해도 요청은 한 번만 나간다.
  Future<RefreshOutcome> _refreshUserToken() {
    return _refreshInFlight ??= _doRefresh().whenComplete(() => _refreshInFlight = null);
  }

  Future<RefreshOutcome> _doRefresh() async {
    final current = userToken.value;
    if (current == null) return RefreshOutcome.rejected;
    if (current.refreshToken.isEmpty) {
      await _clearUserToken(reason: 'refresh token 없음');
      return RefreshOutcome.rejected;
    }

    final url = '${TidalConfig.authBaseUrl}/token';
    AppLogger.log('TIDAL_AUTH', 'POST $url (grant_type=refresh_token)', type: LogType.network);
    try {
      final response = await _dio.post(
        url,
        data: {
          'client_id': TidalConfig.clientId,
          'grant_type': 'refresh_token',
          'refresh_token': current.refreshToken,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'Authorization': 'Basic ${_basicAuth()}'},
        ),
      );
      final data = response.data;
      final token = AuthToken(
        accessToken: data['access_token'] as String,
        refreshToken: data['refresh_token'] as String? ?? current.refreshToken,
        expiresAt: DateTime.now().add(Duration(seconds: (data['expires_in'] as num?)?.toInt() ?? 86400)),
        userId: current.userId,
      );
      await _setUserToken(token);
      AppLogger.log('TIDAL_AUTH', '사용자 토큰 갱신 성공', type: LogType.success);
      return RefreshOutcome.success;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 400 || status == 401) {
        _logError('refresh token 거부됨, 재로그인 필요', e);
        await _clearUserToken(reason: 'refresh 거부');
        return RefreshOutcome.rejected;
      }
      _logError('토큰 갱신 일시 실패 (토큰 유지)', e);
      return RefreshOutcome.temporaryFailure;
    } catch (e) {
      _logError('토큰 갱신 예외 (토큰 유지)', e);
      return RefreshOutcome.temporaryFailure;
    }
  }

  /// 네이티브 SDK가 토큰 오류를 보고했을 때 호출된다. 새 자격 증명을 돌려준다.
  Future<Map<String, Object>?> _provideTokenToNative() async {
    await _ensureLoaded();
    if (userToken.value == null) return null;
    final outcome = await _refreshUserToken();
    final token = userToken.value;
    if (outcome != RefreshOutcome.success || token == null) return null;
    return {
      'userId': token.userId,
      'accessToken': token.accessToken,
      'expiresInSeconds': _remainingSeconds(token),
    };
  }

  // ──────────────────────────────────────────────
  // 상태 변경
  // ──────────────────────────────────────────────

  /// 사용자 토큰을 저장하고 네이티브와 화면에 알린다.
  Future<void> saveToken(AuthToken token) => _setUserToken(token);

  Future<void> _setUserToken(AuthToken token) async {
    _loaded = true;
    userToken.value = token;
    await _storageService.saveUserToken(token);
    await _pushToNative(token);
  }

  Future<void> _pushToNative(AuthToken token) => _native.setUserCredentials(
        userId: token.userId,
        accessToken: token.accessToken,
        expiresInSeconds: _remainingSeconds(token),
      );

  Future<void> _clearUserToken({required String reason}) async {
    AppLogger.log('TIDAL_AUTH', '사용자 토큰 삭제 ($reason)', type: LogType.warning);
    userToken.value = null;
    await _storageService.deleteUserToken();
    await _native.clearUserCredentials();
  }

  /// 로그아웃. 재생 정지는 호출하는 쪽에서 먼저 처리한다.
  Future<void> logout() async {
    _loaded = true;
    await _clearUserToken(reason: '로그아웃');
    AppLogger.log('TIDAL_AUTH', '로그아웃 완료', type: LogType.info);
  }

  // ──────────────────────────────────────────────
  // 유틸
  // ──────────────────────────────────────────────

  static int _remainingSeconds(AuthToken token) {
    final seconds = token.expiresAt.difference(DateTime.now()).inSeconds;
    return seconds < 60 ? 60 : seconds;
  }

  static String _basicAuth() => base64Encode(utf8.encode('${TidalConfig.clientId}:${TidalConfig.clientSecret}'));

  static void _logError(String message, Object e) {
    final detail = e is DioException ? 'HTTP ${e.response?.statusCode ?? e.type.name}' : e.toString();
    AppLogger.log('TIDAL_AUTH', '$message: $detail', type: LogType.error);
  }
}
