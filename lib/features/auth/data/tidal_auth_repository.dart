import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../core/config/tidal_config.dart';
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
                connectTimeout: const Duration(seconds: 3),
                receiveTimeout: const Duration(seconds: 3),
              ),
            );

  AuthToken? get currentToken => _currentToken;

  Future<AuthToken?> autoLogin() async {
    final token = await _storageService.getToken();
    if (token == null) {
      _currentToken = null;
      return null;
    }
    if (token.isExpired) {
      final refreshed = await refreshToken(token.refreshToken);
      _currentToken = refreshed;
      return refreshed;
    }
    _currentToken = token;
    return token;
  }

  /// Obtains App-level access token via Client Credentials Grant
  Future<AuthToken?> authenticateClientCredentials() async {
    try {
      final basicAuth = base64Encode(utf8.encode('${TidalConfig.clientId}:${TidalConfig.clientSecret}'));
      final response = await _dio.post(
        '${TidalConfig.authBaseUrl}/token',
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
      return token;
    } catch (_) {
      return null;
    }
  }

  /// Refreshes user access token using refresh_token
  Future<AuthToken?> refreshToken(String refreshToken) async {
    if (refreshToken.isEmpty) {
      return authenticateClientCredentials();
    }
    try {
      final response = await _dio.post(
        '${TidalConfig.authBaseUrl}/token',
        data: {
          'client_id': TidalConfig.clientId,
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
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
      return token;
    } catch (_) {
      return null;
    }
  }

  /// Initiates Tidal Device Code Flow for User Login
  Future<Map<String, dynamic>?> startDeviceCodeLogin() async {
    try {
      final response = await _dio.post(
        '${TidalConfig.authBaseUrl}/device_authorization',
        data: {
          'client_id': TidalConfig.clientId,
          'scope': 'r_usr w_usr',
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      return response.data as Map<String, dynamic>?;
    } catch (_) {
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
  }
}
