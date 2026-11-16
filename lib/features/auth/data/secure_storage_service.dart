import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/models/auth_token.dart';

/// 토큰을 Android 암호화 저장소에 보관한다.
///
/// 사용자 OAuth 토큰과 앱 단위(client credentials) 토큰을 서로 다른 키에 저장해,
/// 비로그인 상태에서 받은 앱 토큰이 사용자 로그인 정보를 덮어쓰지 않게 한다.
class SecureStorageService {
  final FlutterSecureStorage _storage;

  static const userTokenKey = 'tidal_user_token';
  static const clientTokenKey = 'tidal_client_token';

  /// 1단계 이전 버전이 사용자·앱 토큰을 구분 없이 저장하던 키.
  static const legacyTokenKey = 'tidal_auth_token';

  SecureStorageService({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  Future<void> saveUserToken(AuthToken token) => _write(userTokenKey, token);
  Future<AuthToken?> getUserToken() => _read(userTokenKey);
  Future<void> deleteUserToken() => _storage.delete(key: userTokenKey);

  Future<void> saveClientToken(AuthToken token) => _write(clientTokenKey, token);
  Future<AuthToken?> getClientToken() => _read(clientTokenKey);
  Future<void> deleteClientToken() => _storage.delete(key: clientTokenKey);

  /// 옛 키에 남은 토큰을 새 구조로 옮긴다.
  ///
  /// refresh token과 userId가 모두 있으면 사용자 토큰으로 간주해 옮기고,
  /// 그렇지 않으면 앱 토큰이 섞여 들어간 것이므로 버린다. 옛 키는 항상 삭제한다.
  /// 이미 사용자 토큰이 있으면 덮어쓰지 않는다.
  Future<void> migrateLegacyToken() async {
    final legacy = await _read(legacyTokenKey);
    if (legacy == null) {
      // 손상된 값이 남아 있을 수 있으므로 키 자체는 지운다.
      await _storage.delete(key: legacyTokenKey);
      return;
    }
    final isUserToken = legacy.refreshToken.isNotEmpty && legacy.userId.isNotEmpty;
    if (isUserToken && await getUserToken() == null) {
      await saveUserToken(legacy);
    }
    await _storage.delete(key: legacyTokenKey);
  }

  Future<void> _write(String key, AuthToken token) => _storage.write(key: key, value: jsonEncode(token.toJson()));

  Future<AuthToken?> _read(String key) async {
    final jsonStr = await _storage.read(key: key);
    if (jsonStr == null || jsonStr.isEmpty) return null;
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return AuthToken.fromJson(map);
    } catch (_) {
      return null;
    }
  }
}
