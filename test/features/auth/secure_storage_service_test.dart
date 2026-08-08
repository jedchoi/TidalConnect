import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tidal_connect_lite/features/auth/domain/models/auth_token.dart';
import 'package:tidal_connect_lite/features/auth/data/secure_storage_service.dart';
import 'package:tidal_connect_lite/features/auth/data/tidal_auth_repository.dart';

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
  group('AuthToken Tests', () {
    test('AuthToken serialization and expiry check', () {
      final now = DateTime.now();
      final token = AuthToken(
        accessToken: 'access_123',
        refreshToken: 'refresh_456',
        expiresAt: now.add(const Duration(hours: 1)),
      );

      final json = token.toJson();
      final restored = AuthToken.fromJson(json);

      expect(restored.accessToken, 'access_123');
      expect(restored.refreshToken, 'refresh_456');
      expect(restored.isExpired, false);
    });

    test('AuthToken isExpired returns true when within 5 minutes buffer threshold', () {
      final now = DateTime.now();
      final expiringSoonToken = AuthToken(
        accessToken: 'access_123',
        refreshToken: 'refresh_456',
        expiresAt: now.add(const Duration(minutes: 4)), // less than 5 min left
      );

      expect(expiringSoonToken.isExpired, true);
    });

    test('AuthToken isExpired returns true when past expiry', () {
      final expiredToken = AuthToken(
        accessToken: 'old_acc',
        refreshToken: 'old_ref',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 10)),
      );

      expect(expiredToken.isExpired, true);
    });
  });

  group('SecureStorageService Tests', () {
    late FakeFlutterSecureStorage fakeStorage;
    late SecureStorageService storageService;

    setUp(() {
      fakeStorage = FakeFlutterSecureStorage();
      storageService = SecureStorageService(storage: fakeStorage);
    });

    test('saveToken writes token JSON to secure storage', () async {
      final token = AuthToken(
        accessToken: 'acc_123',
        refreshToken: 'ref_456',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      await storageService.saveToken(token);

      final storedValue = await fakeStorage.read(key: 'tidal_auth_token');
      expect(storedValue, isNotNull);
      expect(storedValue, contains('acc_123'));
      expect(storedValue, contains('ref_456'));
    });

    test('getToken returns AuthToken when found in secure storage', () async {
      final token = AuthToken(
        accessToken: 'acc_123',
        refreshToken: 'ref_456',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      await fakeStorage.write(
        key: 'tidal_auth_token',
        value: jsonEncode(token.toJson()),
      );

      final result = await storageService.getToken();

      expect(result, isNotNull);
      expect(result!.accessToken, 'acc_123');
      expect(result.refreshToken, 'ref_456');
    });

    test('getToken returns null when not found', () async {
      final result = await storageService.getToken();

      expect(result, isNull);
    });

    test('deleteToken and clearToken remove token from storage', () async {
      final token = AuthToken(
        accessToken: 'acc_123',
        refreshToken: 'ref_456',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      await storageService.saveToken(token);
      expect(await storageService.getToken(), isNotNull);

      await storageService.deleteToken();
      expect(await storageService.getToken(), isNull);

      await storageService.saveToken(token);
      await storageService.clearToken();
      expect(await storageService.getToken(), isNull);
    });
  });

  group('TidalAuthRepository Tests', () {
    late FakeFlutterSecureStorage fakeStorage;
    late SecureStorageService storageService;
    late TidalAuthRepository repository;

    setUp(() {
      fakeStorage = FakeFlutterSecureStorage();
      storageService = SecureStorageService(storage: fakeStorage);
      repository = TidalAuthRepository(storageService: storageService);
    });

    test('autoLogin returns token if valid and not expired', () async {
      final validToken = AuthToken(
        accessToken: 'acc_valid',
        refreshToken: 'ref_valid',
        expiresAt: DateTime.now().add(const Duration(hours: 2)),
      );

      await storageService.saveToken(validToken);

      final result = await repository.autoLogin();

      expect(result, isNotNull);
      expect(result!.accessToken, 'acc_valid');
      expect(repository.currentToken?.accessToken, 'acc_valid');
    });

    test('autoLogin returns null if token is expired', () async {
      final expiredToken = AuthToken(
        accessToken: 'acc_expired',
        refreshToken: 'ref_expired',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );

      await storageService.saveToken(expiredToken);

      final result = await repository.autoLogin();

      expect(result, isNull);
      expect(repository.currentToken, isNull);
    });

    test('autoLogin returns null if no token stored', () async {
      final result = await repository.autoLogin();

      expect(result, isNull);
      expect(repository.currentToken, isNull);
    });

    test('saveToken updates currentToken and persists to storage', () async {
      final token = AuthToken(
        accessToken: 'acc_new',
        refreshToken: 'ref_new',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      await repository.saveToken(token);

      expect(repository.currentToken?.accessToken, 'acc_new');
      final storedToken = await storageService.getToken();
      expect(storedToken?.accessToken, 'acc_new');
    });

    test('logout clears currentToken and deletes from storage', () async {
      final token = AuthToken(
        accessToken: 'acc_123',
        refreshToken: 'ref_456',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      await repository.saveToken(token);
      expect(repository.currentToken, isNotNull);

      await repository.logout();

      expect(repository.currentToken, isNull);
      expect(await storageService.getToken(), isNull);
    });
  });
}
