import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tidal_connect_lite/core/native/tidal_sdk_native_bridge.dart';

import '../../helpers/fake_native_channel.dart';
import '../../helpers/playback_fixtures.dart';

// TidalSdkNativeBridge.registerTrackStream 테스트. 규칙 ID(NB-xx)는
// aidlc-docs/construction/dash-seek/functional-design/business-rules.md 4절을 가리킨다.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VoidCallback restoreLogs;
  setUpAll(() => restoreLogs = muteDebugLogs());
  tearDownAll(() => restoreLogs());

  late FakeNativeChannel channel;
  setUp(() {
    channel = FakeNativeChannel()..install();
    addTearDown(channel.uninstall);
  });

  const url = '$fakeProxyOrigin/audio/0000000000000101.mp4';

  Future<ProxyRegistration> register({Duration? startPosition}) => startPosition == null
      ? TidalSdkNativeBridge.registerTrackStream(trackId: '101', manifestXml: '<MPD/>', allowedHost: fakeSpeakerHost)
      : TidalSdkNativeBridge.registerTrackStream(
          trackId: '101',
          manifestXml: '<MPD/>',
          allowedHost: fakeSpeakerHost,
          startPosition: startPosition,
        );

  group('registerTrackStream', () {
    test('[NB-01] 시작 위치를 밀리초 정수 startPositionMs로 더해 보낸다', () async {
      // NB-01: 기존 인자 5개는 그대로이고 startPositionMs가 더해진다(42.9초 → 42900).
      await TidalSdkNativeBridge.registerTrackStream(
        trackId: '101',
        directUrl: 'https://cdn.example.test/tracks/direct.flac',
        manifestXml: '<MPD id="m"/>',
        allowedHost: fakeSpeakerHost,
        mimeType: 'audio/flac',
        startPosition: const Duration(seconds: 42, milliseconds: 900),
      );

      expect(channel.argumentsOf('registerTrackStream').single, {
        'trackId': '101',
        'directUrl': 'https://cdn.example.test/tracks/direct.flac',
        'manifestXml': '<MPD id="m"/>',
        'allowedHost': fakeSpeakerHost,
        'mimeType': 'audio/flac',
        'startPositionMs': 42900,
      });
    });

    test('[NB-01] 시작 위치를 생략하면 startPositionMs는 0이다', () async {
      // NB-01: 생략하면 0(키가 빠지면 실패).
      await register();

      expect(channel.argumentsOf('registerTrackStream').single['startPositionMs'], 0);
    });

    test('[NB-02] 응답의 proxyUrl과 startOffsetMs를 주소와 시작 오프셋으로 돌려준다', () async {
      // NB-02: startOffsetMs는 밀리초(28000 → 28초).
      channel.responses['registerTrackStream'] = (_) => {'proxyUrl': url, 'startOffsetMs': 28000};

      final registration = await register(startPosition: const Duration(seconds: 30));

      expect(registration.url, url);
      expect(registration.startOffset, const Duration(milliseconds: 28000));
    });

    test('[NB-02] startOffsetMs가 없거나 숫자가 아니면 시작 오프셋은 0이다', () async {
      // NB-02: 주소는 그대로 돌려주고 오프셋만 0.
      final responses = <String, Map<String, Object?>>{
        '없음': {'proxyUrl': url},
        'null': {'proxyUrl': url, 'startOffsetMs': null},
        '숫자가 아닌 문자열': {'proxyUrl': url, 'startOffsetMs': 'abc'},
      };
      for (final MapEntry(key: reason, value: response) in responses.entries) {
        channel.responses['registerTrackStream'] = (_) => response;

        final registration = await register(startPosition: const Duration(seconds: 30));

        expect(registration.url, url, reason: reason);
        expect(registration.startOffset, Duration.zero, reason: reason);
      }
    });

    test('[NB-03] 채널 오류면 주소는 빈 문자열, 시작 오프셋은 0이다', () async {
      // NB-03: 예외를 밖으로 내지 않는다.
      channel.failing.add('registerTrackStream');

      final registration = await register(startPosition: const Duration(seconds: 30));

      expect(registration.url, '');
      expect(registration.startOffset, Duration.zero);
    });

    test('[NB-03] 응답에 proxyUrl이 없으면 startOffsetMs가 있어도 주소는 빈 문자열, 시작 오프셋은 0이다', () async {
      // NB-03: 주소가 없는 등록은 실패이므로 오프셋도 쓰지 않는다.
      channel.responses['registerTrackStream'] = (_) => {'startOffsetMs': 28000};

      final registration = await register(startPosition: const Duration(seconds: 30));

      expect(registration.url, '');
      expect(registration.startOffset, Duration.zero);
    });
  });
}
