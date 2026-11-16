import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tidal_connect_lite/features/auth/data/secure_storage_service.dart';
import 'package:tidal_connect_lite/features/auth/data/tidal_auth_repository.dart';
import 'package:tidal_connect_lite/features/auth/domain/models/auth_token.dart';
import 'secure_storage_service_test.dart' show FakeFlutterSecureStorage;

/// 요청 수를 세고 미리 정한 응답을 돌려주는 Dio 어댑터.
class FakeAdapter implements HttpClientAdapter {
  int requestCount = 0;
  final Future<ResponseBody> Function(RequestOptions options) handler;
  FakeAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    requestCount++;
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(Object body, {int status = 200}) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

class FakeNativeSink implements NativeCredentialsSink {
  final List<String> pushedTokens = [];
  int clearCount = 0;

  @override
  Future<bool> initialize() async => true;

  @override
  Future<void> setUserCredentials({required String userId, required String accessToken, required int expiresInSeconds}) async {
    pushedTokens.add(accessToken);
  }

  @override
  Future<void> clearUserCredentials() async => clearCount++;

  @override
  void setTokenRefresher(Future<Map<String, Object>?> Function() refresher) {}
}

void main() {
  late FakeFlutterSecureStorage fakeStorage;
  late SecureStorageService storage;
  late FakeNativeSink native;

  AuthToken expiredUserToken() => AuthToken(
        accessToken: 'old_access',
        refreshToken: 'refresh_1',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        userId: '42',
      );

  TidalAuthRepository build(FakeAdapter adapter) {
    final dio = Dio()..httpClientAdapter = adapter;
    return TidalAuthRepository(storageService: storage, dio: dio, nativeSink: native);
  }

  setUp(() {
    fakeStorage = FakeFlutterSecureStorage();
    storage = SecureStorageService(storage: fakeStorage);
    native = FakeNativeSink();
  });

  test('valid stored user token is restored and pushed to native', () async {
    await storage.saveUserToken(AuthToken(
      accessToken: 'acc',
      refreshToken: 'ref',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      userId: '42',
    ));
    final adapter = FakeAdapter((_) async => throw StateError('no request expected'));
    final repo = build(adapter);

    final token = await repo.autoLogin();

    expect(token!.accessToken, 'acc');
    expect(repo.isLoggedIn, isTrue);
    expect(native.pushedTokens, ['acc']);
    expect(adapter.requestCount, 0);
  });

  test('concurrent refreshes send a single request', () async {
    await storage.saveUserToken(expiredUserToken());
    final gate = Completer<void>();
    final adapter = FakeAdapter((_) async {
      await gate.future;
      return jsonBody({'access_token': 'new_access', 'expires_in': 3600});
    });
    final repo = build(adapter);

    final calls = [repo.getValidUserToken(), repo.getValidUserToken(), repo.getCatalogToken()];
    await Future<void>.delayed(Duration.zero);
    gate.complete();
    final results = await Future.wait(calls);

    expect(adapter.requestCount, 1);
    expect((results[0] as AuthToken).accessToken, 'new_access');
    expect(results[2], 'new_access');
  });

  test('network error keeps the user logged in', () async {
    await storage.saveUserToken(expiredUserToken());
    final adapter = FakeAdapter((options) async => throw DioException.connectionError(
          requestOptions: options,
          reason: 'offline',
        ));
    final repo = build(adapter);

    final token = await repo.getValidUserToken();

    expect(token, isNull);
    expect(repo.isLoggedIn, isTrue);
    expect(await storage.getUserToken(), isNotNull);
    expect(native.clearCount, 0);
  });

  test('rejected refresh token logs the user out', () async {
    await storage.saveUserToken(expiredUserToken());
    final adapter = FakeAdapter((_) async => jsonBody({'error': 'invalid_grant'}, status: 400));
    final repo = build(adapter);

    final token = await repo.getValidUserToken();

    expect(token, isNull);
    expect(repo.isLoggedIn, isFalse);
    expect(await storage.getUserToken(), isNull);
    expect(native.clearCount, 1);
  });

  test('catalog token falls back to a client token without logging in', () async {
    final adapter = FakeAdapter((_) async => jsonBody({'access_token': 'client_access', 'expires_in': 3600}));
    final repo = build(adapter);

    final catalog = await repo.getCatalogToken();

    expect(catalog, 'client_access');
    expect(repo.isLoggedIn, isFalse);
    expect(await storage.getUserToken(), isNull);
    expect(native.pushedTokens, isEmpty);
  });

  test('logout clears storage and native credentials', () async {
    final repo = build(FakeAdapter((_) async => throw StateError('no request expected')));
    await repo.saveToken(AuthToken(
      accessToken: 'acc',
      refreshToken: 'ref',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      userId: '42',
    ));

    await repo.logout();

    expect(repo.currentToken, isNull);
    expect(await storage.getUserToken(), isNull);
    expect(native.clearCount, 1);
  });
}
