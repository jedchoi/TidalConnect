import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tidal_connect_lite/features/auth/data/secure_storage_service.dart';
import 'package:tidal_connect_lite/features/auth/data/tidal_auth_repository.dart';

/// 테스트 공용 가짜 구현 모음.

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

/// 토큰 발급 결과를 미리 정해 두는 인증 저장소.
class FakeAuthRepository extends TidalAuthRepository {
  FakeAuthRepository({this.catalogToken = 'token-1', this.recoveredToken = 'token-2'})
      : super(storageService: SecureStorageService(storage: FakeFlutterSecureStorage()), nativeSink: FakeNativeSink());

  String? catalogToken;
  String? recoveredToken;
  int recoverCount = 0;

  @override
  Future<String?> getCatalogToken() async => catalogToken;

  @override
  Future<String?> recoverFromUnauthorized() async {
    recoverCount++;
    if (recoveredToken != null) catalogToken = recoveredToken;
    return recoveredToken;
  }
}
