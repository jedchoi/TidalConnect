import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tidal_connect_lite/features/auth/domain/models/auth_token.dart';
import 'package:tidal_connect_lite/features/auth/data/secure_storage_service.dart';

import '../../helpers/fakes.dart';

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
