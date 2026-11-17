import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:tidal_connect_lite/features/auth/domain/models/auth_token.dart';
import 'package:tidal_connect_lite/features/dlna/data/dlna_manager.dart';
import 'package:tidal_connect_lite/features/dlna/domain/models/dlna_device.dart';
import 'package:tidal_connect_lite/features/player/data/backends/dlna_backend.dart';
import 'package:tidal_connect_lite/features/player/data/backends/playback_backend.dart';
import 'package:tidal_connect_lite/features/tidal_api/data/tidal_api_client.dart';
import 'package:tidal_connect_lite/features/tidal_api/domain/models/media_item.dart';

import 'app_overrides.dart';
import 'event_descriptions.dart';
import 'fake_native_channel.dart';
import 'fake_soap_client.dart';
import 'fakes.dart';

// 가짜 값 규칙: 기기 주소는 문서용 예약 대역(192.0.2.0/24), 그 밖의 주소는 `.test` 도메인.
// 실제 토큰·키·집 네트워크 주소를 테스트에 적지 않는다.

/// 가짜 원격 스피커의 주소.
const fakeSpeakerHost = '192.0.2.10';

/// 가짜 프록시(폰)의 주소. 실제 프록시와 같은 형식의 주소를 만든다.
const fakeProxyOrigin = 'http://192.0.2.1:8765';

/// 테스트용 곡.
MediaTrack testTrack(
  String id, {
  int durationSeconds = 180,
  String coverUrl = '',
  String? title,
  String artistName = '가수',
  String albumTitle = '앨범',
}) =>
    MediaTrack(
      id: id,
      title: title ?? '곡 $id',
      artistName: artistName,
      albumTitle: albumTitle,
      coverUrl: coverUrl,
      durationSeconds: durationSeconds,
    );

/// 테스트용 원격 스피커. 제어 URL에 빈 문자열을 주면 그 URL이 없는 기기가 된다.
DlnaDevice remoteSpeaker({
  String udn = 'uuid:speaker-1',
  String name = '거실 스피커',
  String host = fakeSpeakerHost,
  int port = 1400,
  String? locationUrl,
  String? avTransportControlUrl,
  String? renderingControlUrl,
}) =>
    DlnaDevice(
      udn: udn,
      friendlyName: name,
      locationUrl: locationUrl ?? 'http://$host:$port/desc.xml',
      avTransportControlUrl: avTransportControlUrl ?? 'http://$host:$port/AVTransport/control',
      renderingControlUrl: renderingControlUrl ?? 'http://$host:$port/RenderingControl/control',
    );

/// 단일 파일(FLAC) 스트림 정보. 탐색할 수 있다.
TidalPlaybackInfo directStream({
  String url = 'https://cdn.example.test/tracks/direct.flac',
  String mimeType = 'audio/flac',
  String audioQuality = 'LOSSLESS',
  int? bitDepth = 16,
  int? sampleRate = 44100,
}) =>
    TidalPlaybackInfo(
      streamUrl: url,
      manifest: '',
      manifestMimeType: 'application/vnd.tidal.bts',
      mimeType: mimeType,
      audioQuality: audioQuality,
      bitDepth: bitDepth,
      sampleRate: sampleRate,
    );

/// DASH 스트림 정보. 탐색할 수 없다.
TidalPlaybackInfo dashStream({String manifest = '<MPD/>'}) => TidalPlaybackInfo(
      streamUrl: '',
      manifest: manifest,
      manifestMimeType: 'application/dash+xml',
      audioQuality: 'HI_RES_LOSSLESS',
      bitDepth: 24,
      sampleRate: 96000,
    );

/// 만료되지 않은 가짜 사용자 토큰.
AuthToken testUserToken() => AuthToken(
      accessToken: 'user-token-1',
      refreshToken: 'refresh-token-1',
      expiresAt: DateTime.now().add(const Duration(days: 1)),
      userId: 'user-1',
    );

/// 가짜 프록시가 곡마다 돌려주는 주소. 실제 프록시처럼 16자 토큰과 확장자가 붙는다.
String proxyUrlFor(String trackId) => '$fakeProxyOrigin/audio/${trackId.padLeft(16, '0')}.flac';

/// `GetPositionInfo` 응답을 만든다.
Map<String, String> positionInfo({int rel = 0, int duration = 180, String trackUri = ''}) => {
      'RelTime': _hms(rel),
      'TrackDuration': _hms(duration),
      'TrackURI': trackUri,
    };

String _hms(int seconds) {
  final h = seconds ~/ 3600;
  final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}

/// [device]가 선택된 [DlnaManager]. 선택을 저장소에 쓰지 않도록 알림 값만 바꾼다.
DlnaManager managerWithSelection(
  DlnaDevice device, {
  FakeSoapClient? soap,
  FakeSsdpDiscoveryService? ssdp,
}) {
  final manager = DlnaManager.forTesting(ssdpService: ssdp ?? FakeSsdpDiscoveryService(), soapClient: soap);
  manager.selectedDeviceNotifier.value = device;
  return manager;
}

/// 테스트 파일이 실행되는 동안 앱 로그 출력을 끈다. 반환된 함수를 부르면 되돌린다.
///
/// 속성 테스트는 같은 흐름을 수백 번 실행하므로 로그를 그대로 두면 출력이 지나치게 많아진다.
VoidCallback muteDebugLogs() {
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {};
  return () => debugPrint = original;
}

/// 비동기 호출 하나의 결과. `fakeAsync` 안에서는 `await`할 수 없으므로 결과를 여기에 받아 둔다.
class CallResult {
  bool completed = false;
  Object? error;

  /// 예외로 끝났으면 그 [PlaybackException]의 코드.
  String? get errorCode => error is PlaybackException ? (error! as PlaybackException).code : null;
}

/// [future]를 시작하고 결과를 [CallResult]에 받는다.
CallResult capture(Future<void> future) {
  final result = CallResult();
  future.then((_) => result.completed = true, onError: (Object e) {
    result.error = e;
  });
  return result;
}

/// [DlnaBackend] 테스트 묶음.
///
/// 기본 상태는 성공 조건이다: 원격 스피커 선택, 사용자 토큰 있음, 단일 파일 스트림 있음,
/// 프록시 등록 성공, SOAP 명령 성공, 스피커는 재생 중이라고 응답.
/// 각 테스트는 규칙이 요구하는 조건 하나만 바꾼다.
class DlnaBackendHarness {
  DlnaBackendHarness({DlnaDevice? device}) : device = device ?? remoteSpeaker() {
    channel.install();
    channel.responses['registerTrackStream'] =
        (call) => {'proxyUrl': proxyUrlFor((call.arguments as Map)['trackId'] as String)};
    auth.validUserToken = testUserToken();
    api.defaultPlaybackInfo = directStream();
    soap
      ..transportState = 'PLAYING'
      ..positionInfo = positionInfo(rel: 1);
    manager = managerWithSelection(this.device, soap: soap);
    backend = DlnaBackend(auth: auth, api: api, dlna: manager);
    _subscription = backend.events.listen(events.add);
  }

  final DlnaDevice device;
  final channel = FakeNativeChannel();
  final soap = FakeSoapClient();
  final auth = FakeAuthRepository();
  final api = FakeApiClient();
  late final DlnaManager manager;
  late final DlnaBackend backend;
  late final StreamSubscription<BackendEvent> _subscription;

  /// 백엔드가 낸 이벤트(순서대로).
  final events = <BackendEvent>[];

  /// [events]의 한 줄 표현.
  List<String> get described => describeEvents(events);

  /// 재생을 요청하고 비동기 작업을 끝까지 진행시킨다.
  CallResult play(
    FakeAsync async,
    MediaTrack track, {
    Duration startPosition = Duration.zero,
    IsCancelled? isCancelled,
  }) {
    final result = capture(backend.play(track, startPosition: startPosition, isCancelled: isCancelled ?? () => false));
    async.flushMicrotasks();
    return result;
  }

  /// 폴링을 [times]번 돌린다(1초씩 진행).
  void poll(FakeAsync async, [int times = 1]) {
    for (var i = 0; i < times; i++) {
      async.elapse(const Duration(seconds: 1));
    }
  }

  /// 지금까지의 이벤트·호출 기록을 지운다. 준비 단계의 기록을 빼고 볼 때 쓴다.
  void clearRecords() {
    events.clear();
    channel.calls.clear();
    soap.calls.clear();
    api.calls.clear();
  }

  void dispose() {
    _subscription.cancel();
    backend.dispose();
    channel.uninstall();
  }
}
