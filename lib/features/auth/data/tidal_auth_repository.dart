import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../core/config/tidal_config.dart';
import '../../../core/utils/app_logger.dart';
import '../domain/models/auth_token.dart';
import 'secure_storage_service.dart';

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
            );

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
    AppLogger.log('TIDAL_AUTH', '저장된 유효 토큰 자동 로그인 성공 (Access Token Expiry: ${token.expiresAt})', type: LogType.success);
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

  /// Exchanges PKCE Authorization Code for User Access Token & Refresh Token
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
          'scope': 'r_usr w_usr',
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

      final token = AuthToken(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      );

      await saveToken(token);
      AppLogger.log('TIDAL_AUTH', 'Tidal 사용자 PKCE OAuth 로그인 성공! [HTTP ${response.statusCode}] Access Token 저장됨', type: LogType.success);
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

      final token = AuthToken(
        accessToken: accessToken,
        refreshToken: newRefreshToken,
        expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      );

      await saveToken(token);
      AppLogger.log('TIDAL_AUTH', 'OAuth 사용자 토큰 갱신 성공 [HTTP ${response.statusCode}]', type: LogType.success);
      return token;
    } catch (e) {
      AppLogger.log('TIDAL_AUTH', 'OAuth 사용자 토큰 갱신 실패: $e', type: LogType.error);
      return null;
    }
  }

  /// Initiates Tidal Device Code Flow for User Login (for Limited Input Devices)
  Future<Map<String, dynamic>?> startDeviceCodeLogin() async {
    final url = '${TidalConfig.authBaseUrl}/device_authorization';
    AppLogger.log('TIDAL_AUTH', 'POST $url (Device Code 요청)', type: LogType.network);
    try {
      final basicAuth = base64Encode(utf8.encode('${TidalConfig.clientId}:${TidalConfig.clientSecret}'));
      final response = await _dio.post(
        url,
        data: {
          'client_id': TidalConfig.clientId,
          'scope': 'r_usr w_usr',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'Authorization': 'Basic $basicAuth'},
        ),
      );
      AppLogger.log('TIDAL_AUTH', 'Device Code 발급 응답 [HTTP ${response.statusCode}]: ${response.data}', type: LogType.success);
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      if (e is DioException) {
        AppLogger.log('TIDAL_AUTH', 'Device Code 발급 실패 [HTTP ${e.response?.statusCode}]: ${e.response?.data ?? e.message}', type: LogType.error);
      } else {
        AppLogger.log('TIDAL_AUTH', 'Device Code 발급 예외: $e', type: LogType.error);
      }
      return null;
    }
  }

  /// Polls Tidal OAuth token endpoint using device_code until user authorizes
  Future<AuthToken?> pollDeviceCodeToken(String deviceCode) async {
    final url = '${TidalConfig.authBaseUrl}/token';
    final basicAuth = base64Encode(utf8.encode('${TidalConfig.clientId}:${TidalConfig.clientSecret}'));
    try {
      final response = await _dio.post(
        url,
        data: {
          'client_id': TidalConfig.clientId,
          'device_code': deviceCode,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
          'scope': 'r_usr w_usr',
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

      final token = AuthToken(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      );

      await saveToken(token);
      AppLogger.log('TIDAL_AUTH', '사용자 Device Code 인증 성공! Access Token 발급 완료', type: LogType.success);
      return token;
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 400) {
        final err = e.response?.data?['error'] as String?;
        if (err == 'authorization_pending') {
          AppLogger.log('TIDAL_AUTH', '사용자 승인 대기 중 (authorization_pending)...', type: LogType.info);
          return null;
        }
      }
      AppLogger.log('TIDAL_AUTH', 'Device Code 토큰 폴링 중: ${e is DioException ? e.response?.data : e}', type: LogType.warning);
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
