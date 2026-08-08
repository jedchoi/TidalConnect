import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../core/config/tidal_config.dart';
import '../../../core/utils/app_logger.dart';
import '../domain/models/auth_token.dart';
import 'secure_storage_service.dart';

import '../../../core/native/tidal_sdk_native_bridge.dart';

class TidalAuthRepository {
  final SecureStorageService _storageService;
  final Dio _dio;
  AuthToken? _currentToken;

  TidalAuthRepository({SecureStorageService? storageService, Dio? dio})
      : _storageService = storageService ?? SecureStorageService(),
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 5),
              ),
            ) {
    initNativeSdk();
  }

  Future<void> initNativeSdk() async {
    await TidalSdkNativeBridge.initTidalAuth(
      clientId: TidalConfig.clientId,
      clientSecret: TidalConfig.clientSecret,
    );
  }

  AuthToken? get currentToken => _currentToken;

  Future<AuthToken?> autoLogin() async {
    final token = await _storageService.getToken();
    if (token == null) {
      _currentToken = null;
      AppLogger.log('TIDAL_AUTH', '저장된 기존 OAuth 토큰 없음 (로그인 필요)', type: LogType.warning);
      return null;
    }
    if (token.isExpired) {
      AppLogger.log('TIDAL_AUTH', '저장된 토큰 만료됨 -> 토큰 갱신 시도', type: LogType.warning);
      final refreshed = await refreshToken(token.refreshToken);
      _currentToken = refreshed;
      return refreshed;
    }
    _currentToken = token;
    AppLogger.log('TIDAL_AUTH', '저장된 유효 토큰 자동 로그인 성공 (UserId: ${token.userId}, Expiry: ${token.expiresAt})', type: LogType.success);
    return token;
  }

  /// Obtains App-level access token via Client Credentials Grant
  Future<AuthToken?> authenticateClientCredentials() async {
    final url = '${TidalConfig.authBaseUrl}/token';
    AppLogger.log('TIDAL_AUTH', 'POST $url (grant_type=client_credentials, ClientID=${TidalConfig.clientId})', type: LogType.network);
    try {
      final basicAuth = base64Encode(utf8.encode('${TidalConfig.clientId}:${TidalConfig.clientSecret}'));
      final response = await _dio.post(
        url,
        data: {'grant_type': 'client_credentials'},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'Authorization': 'Basic $basicAuth'},
        ),
      );

      final data = response.data;
      final accessToken = data['access_token'] as String;
      final expiresIn = data['expires_in'] as int? ?? 604800;
      final token = AuthToken(
        accessToken: accessToken,
        refreshToken: '',
        expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
        userId: '',
      );

      await saveToken(token);
      AppLogger.log('TIDAL_AUTH', 'OAuth Client Credentials 인증 성공 [HTTP ${response.statusCode}] Access Token 발급됨', type: LogType.success);
      return token;
    } catch (e) {
      if (e is DioException) {
        AppLogger.log('TIDAL_AUTH', 'OAuth 인증 실패 [HTTP ${e.response?.statusCode ?? "CONNECT_ERROR"}]: ${e.response?.data ?? e.message}', type: LogType.error);
      } else {
        AppLogger.log('TIDAL_AUTH', 'OAuth 인증 예외 발생: $e', type: LogType.error);
      }
      return null;
    }
  }

  /// Exchanges PKCE Authorization Code for User Access Token & Refresh Token & UserId
  Future<AuthToken?> exchangeAuthorizationCode({
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) async {
    final url = '${TidalConfig.authBaseUrl}/token';
    AppLogger.log('TIDAL_AUTH', 'POST $url (PKCE Authorization Code 교환 시도, RedirectURI=$redirectUri)', type: LogType.network);
    try {
      final basicAuth = base64Encode(utf8.encode('${TidalConfig.clientId}:${TidalConfig.clientSecret}'));
      final response = await _dio.post(
        url,
        data: {
          'client_id': TidalConfig.clientId,
          'grant_type': 'authorization_code',
          'code': code,
          'code_verifier': codeVerifier,
          'redirect_uri': redirectUri,
          'scope': 'r_usr',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'Authorization': 'Basic $basicAuth'},
        ),
      );

      final data = response.data;
      final accessToken = data['access_token'] as String;
      final refreshToken = data['refresh_token'] as String? ?? '';
      final expiresIn = data['expires_in'] as int? ?? 86400;

      // Extract numeric userId from data['user']['userId'] or data['user_id']
      String userId = '';
      if (data['user'] != null && data['user']['userId'] != null) {
        userId = data['user']['userId'].toString();
      } else if (data['user_id'] != null) {
        userId = data['user_id'].toString();
      }

      // Fallback: If userId is empty, fetch session user info
      if (userId.isEmpty) {
        userId = await _fetchUserIdFromSession(accessToken);
      }

      final token = AuthToken(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
        userId: userId,
      );

      await saveToken(token);
      AppLogger.log('TIDAL_AUTH', 'Tidal 사용자 PKCE OAuth 로그인 성공! [HTTP ${response.statusCode}] UserId=$userId, Access Token 저장됨', type: LogType.success);
      return token;
    } catch (e) {
      if (e is DioException) {
        AppLogger.log('TIDAL_AUTH', 'PKCE 토큰 교환 실패 [HTTP ${e.response?.statusCode}]: ${e.response?.data ?? e.message}', type: LogType.error);
      } else {
        AppLogger.log('TIDAL_AUTH', 'PKCE 토큰 교환 예외: $e', type: LogType.error);
      }
      return null;
    }
  }

  /// Helper to fetch numeric userId from GET https://api.tidal.com/v1/sessions
  Future<String> _fetchUserIdFromSession(String accessToken) async {
    try {
      final response = await _dio.get(
        'https://api.tidal.com/v1/sessions',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final userId = response.data['userId']?.toString() ?? response.data['user']?['userId']?.toString() ?? '';
      AppLogger.log('TIDAL_AUTH', '세션 API 조회를 통해 UserId($userId) 획득', type: LogType.info);
      return userId;
    } catch (e) {
      AppLogger.log('TIDAL_AUTH', '세션 UserId 조회 예외: $e', type: LogType.warning);
      return '';
    }
  }

  /// Refreshes user access token using refresh_token
  Future<AuthToken?> refreshToken(String refreshToken) async {
    if (refreshToken.isEmpty) {
      return null;
    }
    final url = '${TidalConfig.authBaseUrl}/token';
    AppLogger.log('TIDAL_AUTH', 'POST $url (grant_type=refresh_token)', type: LogType.network);
    try {
      final basicAuth = base64Encode(utf8.encode('${TidalConfig.clientId}:${TidalConfig.clientSecret}'));
      final response = await _dio.post(
        url,
        data: {
          'client_id': TidalConfig.clientId,
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
          'scope': 'r_usr',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'Authorization': 'Basic $basicAuth'},
        ),
      );

      final data = response.data;
      final accessToken = data['access_token'] as String;
      final newRefreshToken = data['refresh_token'] as String? ?? refreshToken;
      final expiresIn = data['expires_in'] as int? ?? 86400;

      String userId = _currentToken?.userId ?? '';
      if (userId.isEmpty) {
        userId = await _fetchUserIdFromSession(accessToken);
      }

      final token = AuthToken(
        accessToken: accessToken,
        refreshToken: newRefreshToken,
        expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
        userId: userId,
      );

      await saveToken(token);
      AppLogger.log('TIDAL_AUTH', 'OAuth 사용자 토큰 갱신 성공 [HTTP ${response.statusCode}] UserId=$userId', type: LogType.success);
      return token;
    } catch (e) {
      AppLogger.log('TIDAL_AUTH', 'OAuth 사용자 토큰 갱신 실패: $e', type: LogType.error);
      return null;
    }
  }

  Future<void> saveToken(AuthToken token) async {
    _currentToken = token;
    await _storageService.saveToken(token);
  }

  Future<void> logout() async {
    _currentToken = null;
    await _storageService.deleteToken();
    AppLogger.log('TIDAL_AUTH', '로그아웃 완료 (저장된 토큰 삭제됨)', type: LogType.info);
  }
}
