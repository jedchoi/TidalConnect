import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// MethodChannel `com.example.tidal_connect_lite/tidal_sdk`의 Kotlin 쪽을 대신한다.
///
/// Dart가 보낸 호출을 기록하고, 메서드별로 응답·실패를 정할 수 있다.
/// `setUp`에서 [install]하고 `addTearDown(channel.uninstall)`로 푼다.
class FakeNativeChannel {
  static const channelName = 'com.example.tidal_connect_lite/tidal_sdk';
  static const _channel = MethodChannel(channelName);
  static const _codec = StandardMethodCodec();

  /// 받은 호출(순서대로).
  final List<MethodCall> calls = [];

  /// 메서드별 응답. 지정하지 않은 메서드는 null을 돌려준다.
  final Map<String, Object? Function(MethodCall call)> responses = {};

  /// 여기 든 메서드는 `PlatformException`으로 실패한다.
  final Set<String> failing = {};

  final Map<String, Completer<void>> _holds = {};

  TestDefaultBinaryMessenger get _messenger => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void install() => _messenger.setMockMethodCallHandler(_channel, _handle);

  void uninstall() {
    for (final hold in _holds.values) {
      if (!hold.isCompleted) hold.complete();
    }
    _holds.clear();
    _messenger.setMockMethodCallHandler(_channel, null);
  }

  Future<Object?> _handle(MethodCall call) async {
    calls.add(call);
    final hold = _holds[call.method];
    if (hold != null) await hold.future;
    if (failing.contains(call.method)) {
      throw PlatformException(code: 'TEST_FAILURE', message: '${call.method} 실패(테스트)');
    }
    return responses[call.method]?.call(call);
  }

  /// [method]의 응답을 [release]를 부를 때까지 붙잡아 둔다.
  void hold(String method) => _holds[method] = Completer<void>();

  void release(String method) => _holds.remove(method)?.complete();

  /// 받은 호출의 메서드 이름(순서대로).
  List<String> get methods => calls.map((c) => c.method).toList();

  List<MethodCall> callsOf(String method) => calls.where((c) => c.method == method).toList();

  /// [method] 호출들의 인자 맵.
  List<Map<String, Object?>> argumentsOf(String method) =>
      callsOf(method).map((c) => Map<String, Object?>.from((c.arguments as Map?) ?? const {})).toList();

  /// Kotlin이 Dart로 보내는 호출(`refreshTrackStream`, `refreshUserToken`)을 흉내 낸다.
  /// Dart 쪽 핸들러의 반환값을 돌려준다.
  Future<Object?> invokeFromNative(String method, [Object? arguments]) {
    final completer = Completer<Object?>();
    _messenger.handlePlatformMessage(
      channelName,
      _codec.encodeMethodCall(MethodCall(method, arguments)),
      (ByteData? reply) {
        if (reply == null) {
          completer.complete(null);
          return;
        }
        try {
          completer.complete(_codec.decodeEnvelope(reply));
        } catch (error) {
          completer.completeError(error);
        }
      },
    );
    return completer.future;
  }
}
