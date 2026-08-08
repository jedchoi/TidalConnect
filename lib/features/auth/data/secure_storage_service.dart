import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/models/auth_token.dart';

class SecureStorageService {
  final FlutterSecureStorage _storage;
  static const _tokenKey = 'tidal_auth_token';

  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<void> saveToken(AuthToken token) async {
    final jsonStr = jsonEncode(token.toJson());
    await _storage.write(key: _tokenKey, value: jsonStr);
  }

  Future<AuthToken?> getToken() async {
    final jsonStr = await _storage.read(key: _tokenKey);
    if (jsonStr == null || jsonStr.isEmpty) return null;
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return AuthToken.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteToken() async {
    await _storage.delete(key: _tokenKey);
  }
}
