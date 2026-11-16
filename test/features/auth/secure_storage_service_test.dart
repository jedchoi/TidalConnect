import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tidal_connect_lite/features/auth/domain/models/auth_token.dart';
import 'package:tidal_connect_lite/features/auth/data/secure_storage_service.dart';

class FakeFlutterSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _data = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _data[key];
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.remove(key);
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.clear();
  }

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return Map.from(_data);
  }

  @override
  Future<bool> containsKey({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _data.containsKey(key);
  }

  @override
  IOSOptions get iOptions => throw UnimplementedError();

  @override
  AndroidOptions get aOptions => throw UnimplementedError();

  @override
  LinuxOptions get lOptions => throw UnimplementedError();

  @override
  WebOptions get webOptions => throw UnimplementedError();

  @override
  MacOsOptions get mOptions => throw UnimplementedError();

  @override
  WindowsOptions get wOptions => throw UnimplementedError();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('AuthToken', () {
    test('serialization and expiry check', () {
      final token = AuthToken(
        accessToken: 'access_123',
        refreshToken: 'refresh_456',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        userId: '42',
      );
      final restored = AuthToken.fromJson(token.toJson());
      expect(restored.accessToken, 'access_123');
      expect(restored.refreshToken, 'refresh_456');
      expect(restored.userId, '42');
      expect(restored.isExpired, false);
    });

    test('isExpired is true within the 5 minute buffer', () {
      final token = AuthToken(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: DateTime.now().add(const Duration(minutes: 4)),
      );
      expect(token.isExpired, true);
    });
  });

  group('SecureStorageService', () {
    late FakeFlutterSecureStorage fakeStorage;
    late SecureStorageService storage;

    AuthToken token(String access, {String refresh = 'ref', String userId = '42'}) => AuthToken(
          accessToken: access,
          refreshToken: refresh,
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          userId: userId,
        );

    setUp(() {
      fakeStorage = FakeFlutterSecureStorage();
      storage = SecureStorageService(storage: fakeStorage);
    });

    test('user and client tokens are stored under separate keys', () async {
      await storage.saveUserToken(token('user_acc'));
      await storage.saveClientToken(token('client_acc', refresh: '', userId: ''));

      expect((await storage.getUserToken())!.accessToken, 'user_acc');
      expect((await storage.getClientToken())!.accessToken, 'client_acc');
      expect(await fakeStorage.read(key: SecureStorageService.userTokenKey), contains('user_acc'));
      expect(await fakeStorage.read(key: SecureStorageService.clientTokenKey), contains('client_acc'));
    });

    test('saving a client token never touches the user token', () async {
      await storage.saveUserToken(token('user_acc'));
      await storage.saveClientToken(token('client_acc', refresh: '', userId: ''));
      expect((await storage.getUserToken())!.accessToken, 'user_acc');
    });

    test('migrates a legacy user token and removes the legacy key', () async {
      await fakeStorage.write(
        key: SecureStorageService.legacyTokenKey,
        value: jsonEncode(token('legacy_user').toJson()),
      );

      await storage.migrateLegacyToken();

      expect((await storage.getUserToken())!.accessToken, 'legacy_user');
      expect(await fakeStorage.read(key: SecureStorageService.legacyTokenKey), isNull);
    });

    test('drops a legacy client token instead of treating it as a login', () async {
      await fakeStorage.write(
        key: SecureStorageService.legacyTokenKey,
        value: jsonEncode(token('legacy_client', refresh: '', userId: '').toJson()),
      );

      await storage.migrateLegacyToken();

      expect(await storage.getUserToken(), isNull);
      expect(await fakeStorage.read(key: SecureStorageService.legacyTokenKey), isNull);
    });

    test('deleteUserToken removes only the user token', () async {
      await storage.saveUserToken(token('user_acc'));
      await storage.saveClientToken(token('client_acc', refresh: '', userId: ''));
      await storage.deleteUserToken();
      expect(await storage.getUserToken(), isNull);
      expect(await storage.getClientToken(), isNotNull);
    });
  });
}
