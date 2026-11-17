import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiri_check/kiri_check.dart' show combine2, forAll, property;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tidal_connect_lite/features/dlna/domain/models/dlna_device.dart';
import 'package:tidal_connect_lite/features/player/data/backends/playback_backend.dart';

import '../../helpers/generators.dart';
import '../../helpers/pbt_config.dart';
import '../../helpers/playback_fixtures.dart';

// DlnaBackend 테스트. 규칙 ID(DB-xx)와 속성 ID(P-DB-x)는
// aidlc-docs/construction/dart-playback-tests/functional-design/ 의
// business-rules.md 3절, business-logic-model.md 5절을 가리킨다.
// DB-50 이후의 규칙, 바뀐 규칙(DB-12 · 13 · 17 · 39 · 45), 속성 P-DB-6 · 7은
// aidlc-docs/construction/dash-seek/functional-design/business-rules.md 5절을 가리킨다.
//
// 1초 폴링을 실제로 기다리지 않도록 모든 테스트를 fakeAsync 안에서 실행한다.
// fakeAsync 본문에서는 await할 수 없으므로 호출 결과는 CallResult에 받아 두고
// flushMicrotasks()로 진행시킨다.

/// 폴링의 모델. business-logic-model.md 3.2의 상태 기계를 옮긴 것이다.
/// 응답 하나를 받아, 그 응답으로 나와야 하는 이벤트(describeEvent 형식)를 돌려준다.
class PollModel {
  PollModel({required this.trackId, required int trackSeconds}) : _duration = trackSeconds > 0 ? trackSeconds : null;

  final String trackId;

  /// 폴링 중인지. 곡이 끝나거나, 스피커 쪽에서 멈추거나, 응답이 3회 연속 없으면 false가 된다.
  bool polling = true;

  int? _duration;
  int _lastPosition = 0;
  bool _sawPlaying = false;
  int _silentPolls = 0;

  List<String> step(PollResponse response) {
    if (!polling) return const [];

    final rel = response.relSeconds;
    if (response.state == null && rel == null) {
      _silentPolls++;
      if (_silentPolls < 3) return const [];
      polling = false;
      return const ['state(stopped)', 'error(DLNA_UNREACHABLE)'];
    }
    _silentPolls = 0;

    final out = <String>[];
    if (rel != null) {
      if (response.durationSeconds > 0) _duration = response.durationSeconds;
      if (rel > 0) _lastPosition = rel;
      out.add('position($rel/${_duration ?? '-'})');
    }
    switch (response.state) {
      case 'PLAYING':
        _sawPlaying = true;
        out.add('state(playing)');
      case 'TRANSITIONING':
        out.add('state(playing,buffering)');
      case 'PAUSED_PLAYBACK':
        out.add('state(stopped)');
      case 'STOPPED' || 'NO_MEDIA_PRESENT' when _sawPlaying:
        polling = false;
        final duration = _duration;
        final nearEnd = duration == null || _lastPosition >= duration - 3;
        out.add(nearEnd ? 'ended($trackId)' : 'state(stopped)');
    }
    return out;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  configurePbt();

  late VoidCallback restoreLogs;
  setUpAll(() => restoreLogs = muteDebugLogs());
  tearDownAll(() => restoreLogs());

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// 묶음을 만들어 [body]를 가짜 시간 안에서 실행하고 정리한다.
  void withHarness(void Function(FakeAsync async, DlnaBackendHarness h) body, {DlnaDevice? device}) {
    fakeAsync((async) {
      final h = DlnaBackendHarness(device: device);
      try {
        body(async, h);
      } finally {
        h.dispose();
        async.flushMicrotasks();
      }
    });
  }

  /// 곡 [id]를 재생해 폴링 중인 상태로 만든 뒤 준비 단계의 기록을 지운다.
  void startPlaying(FakeAsync async, DlnaBackendHarness h, {String id = '101', int durationSeconds = 180}) {
    final result = h.play(async, testTrack(id, durationSeconds: durationSeconds));
    expect(result.error, isNull);
    h.clearRecords();
  }

  /// 다음 폴링에서 스피커가 돌려줄 응답을 정한다.
  void respond(DlnaBackendHarness h, {String? state, int? rel, int duration = 0, String trackUri = ''}) {
    h.soap.transportStates.add(state);
    h.soap.positionInfos.add(rel == null ? null : positionInfo(rel: rel, duration: duration, trackUri: trackUri));
  }

  /// DASH 곡 [id]를 처음부터 재생해 폴링 중인 상태로 만든다(시작 오프셋 0).
  void startDash(
    FakeAsync async,
    DlnaBackendHarness h, {
    String id = '101',
    int durationSeconds = 180,
    String manifest = '<MPD/>',
  }) {
    h.api.playbackInfos[id] = dashStream(manifest: manifest);
    startPlaying(async, h, id: id, durationSeconds: durationSeconds);
  }

  /// DASH 곡 [id]를 [offsetSeconds]초에서 시작해 폴링 중인 상태로 만든다.
  /// 프록시는 같은 값을 시작 오프셋으로 답한다(이후의 시작 위치 있는 등록에도 같은 값으로 답한다).
  void startDashAt(
    FakeAsync async,
    DlnaBackendHarness h, {
    required int offsetSeconds,
    String id = '101',
    int durationSeconds = 180,
  }) {
    h.api.playbackInfos[id] = dashStream();
    h.answerStartOffset(Duration(seconds: offsetSeconds));
    final result = h.play(
      async,
      testTrack(id, durationSeconds: durationSeconds),
      startPosition: Duration(seconds: offsetSeconds),
    );
    expect(result.error, isNull);
    h.clearRecords();
  }

  /// 다음 곡 등록(갭리스)을 요청하고 끝까지 진행시킨다.
  void registerNext(FakeAsync async, DlnaBackendHarness h, String? id, {int durationSeconds = 240}) {
    h.backend.setNext(id == null ? null : testTrack(id, durationSeconds: durationSeconds));
    async.flushMicrotasks();
  }

  bool? lastStreamingLock(DlnaBackendHarness h) {
    final calls = h.channel.argumentsOf('setStreamingLock');
    return calls.isEmpty ? null : calls.last['enabled'] as bool?;
  }

  group('재생 요청', () {
    test('[DB-01] 재생을 시작할 때 진행 중이던 폴링을 멈추고 폰 재생을 멈춘다', () {
      withHarness((async, h) {
        h.play(async, testTrack('101'));
        expect(h.channel.methods.first, 'stopTrack');

        h.clearRecords();
        h.play(async, testTrack('102'));

        expect(h.channel.methods, ['setStreamingLock', 'stopTrack', 'registerTrackStream', 'setStreamingLock']);
        expect(h.channel.argumentsOf('setStreamingLock').map((a) => a['enabled']), [false, true]);
      });
    });

    test('[DB-02] 사용자 토큰이 없으면 NOT_LOGGED_IN 예외를 던지고 스트림 조회도 스피커 명령도 하지 않는다', () {
      withHarness((async, h) {
        h.auth.validUserToken = null;

        final result = h.play(async, testTrack('101'));

        expect(result.errorCode, 'NOT_LOGGED_IN');
        expect(h.api.calls, isEmpty);
        expect(h.channel.methods, ['stopTrack']);
        expect(h.soap.calls, isEmpty);
        expect(h.events, isEmpty);
      });
    });

    test('[DB-03] 스트림 정보를 받지 못하면 NO_STREAM 예외를 던지고 스피커 명령을 하지 않는다', () {
      withHarness((async, h) {
        h.api.defaultPlaybackInfo = null;

        final result = h.play(async, testTrack('101'));

        expect(result.errorCode, 'NO_STREAM');
        expect(h.channel.methods, ['stopTrack']);
        expect(h.soap.calls, isEmpty);
        expect(h.events, isEmpty);
      });
    });

    test('[DB-04] 스트림은 기본 LOSSLESS로 요청하고, 음질을 바꾸면 그 음질로 요청한다', () {
      withHarness((async, h) {
        h.play(async, testTrack('101'));
        h.backend.setAudioQuality('HI_RES_LOSSLESS');
        async.flushMicrotasks();
        h.play(async, testTrack('102'));

        expect(h.api.calls, ['getPlaybackInfo:101:LOSSLESS', 'getPlaybackInfo:102:HI_RES_LOSSLESS']);
      });
    });

    test('[DB-05] 프록시 등록에 곡 ID, 스트림 주소, 스피커 주소, MIME을 넘긴다', () {
      withHarness((async, h) {
        h.play(async, testTrack('101'));

        expect(h.channel.argumentsOf('registerTrackStream').single, {
          'trackId': '101',
          'directUrl': 'https://cdn.example.test/tracks/direct.flac',
          'manifestXml': '',
          'allowedHost': fakeSpeakerHost,
          'mimeType': 'audio/flac',
          'startPositionMs': 0,
        });
      });
    });

    test('[DB-05] DASH 스트림은 매니페스트를 넘기고, 스피커 주소를 알 수 없으면 빈 값을 넘긴다', () {
      withHarness((async, h) {
        h.api.defaultPlaybackInfo = dashStream(manifest: '<MPD id="m"/>');

        h.play(async, testTrack('101'));

        final args = h.channel.argumentsOf('registerTrackStream').single;
        expect(args['directUrl'], '');
        expect(args['manifestXml'], '<MPD id="m"/>');
        expect(args['allowedHost'], '');
      }, device: remoteSpeaker(locationUrl: ''));
    });

    test('[DB-06] 프록시 등록이 실패하면(예: Wi-Fi 없음) PROXY_FAILED 예외를 던지고 스피커 명령을 하지 않는다', () {
      withHarness((async, h) {
        h.channel.failing.add('registerTrackStream');

        final result = h.play(async, testTrack('101'));

        expect(result.errorCode, 'PROXY_FAILED');
        expect(h.soap.calls, isEmpty);
        expect(h.events, isEmpty);
      });
    });

    test('[DB-06] 프록시 응답에 주소가 없어도 PROXY_FAILED 예외를 던진다', () {
      withHarness((async, h) {
        h.channel.responses['registerTrackStream'] = (_) => <String, Object?>{};

        final result = h.play(async, testTrack('101'));

        expect(result.errorCode, 'PROXY_FAILED');
        expect(h.soap.calls, isEmpty);
      });
    });

    test('[DB-07] 성공하면 곡 시작 알림, 스피커 명령, 재생 상태 알림 순서로 진행하고 폴링을 시작한다', () {
      withHarness((async, h) {
        final result = h.play(async, testTrack('101'));

        expect(result.error, isNull);
        expect(result.completed, isTrue);
        expect(h.described, ['started(101)', 'state(playing,buffering)']);
        expect(h.soap.actions, ['Stop', 'SetAVTransportURI', 'Play']);
        expect(h.soap.lastStreamUrl, proxyUrlFor('101'));
        expect(h.channel.methods, ['stopTrack', 'registerTrackStream', 'setStreamingLock']);
        expect(lastStreamingLock(h), isTrue);

        h.clearRecords();
        h.poll(async);
        expect(h.soap.actions, unorderedEquals(['GetTransportInfo', 'GetPositionInfo']));
      });
    });

    test('[DB-08] 곡 시작 알림에 곡의 길이와 스트림 음질을 싣는다', () {
      withHarness((async, h) {
        h.api.defaultPlaybackInfo = directStream(audioQuality: 'HI_RES_LOSSLESS', bitDepth: 24, sampleRate: 96000);

        h.play(async, testTrack('101', durationSeconds: 205));

        final started = h.events.first as BackendTrackStarted;
        expect(started.trackId, '101');
        expect(started.duration, const Duration(seconds: 205));
        expect(started.quality!.audioQuality, 'HI_RES_LOSSLESS');
        expect(started.quality!.bitDepth, 24);
        expect(started.quality!.sampleRate, 96000);
      });
    });

    test('[DB-08] 길이가 0인 곡은 길이를 모르는 것으로 알린다', () {
      withHarness((async, h) {
        h.play(async, testTrack('101', durationSeconds: 0));

        expect((h.events.first as BackendTrackStarted).duration, isNull);
      });
    });

    test('[DB-09] 스피커에 곡 제목·가수·앨범·커버·길이·MIME을 메타데이터로 보낸다', () {
      withHarness((async, h) {
        h.play(
          async,
          testTrack(
            '101',
            title: '제목',
            artistName: '가수 이름',
            albumTitle: '앨범 이름',
            coverUrl: 'https://resources.example.test/cover.jpg',
            durationSeconds: 205,
          ),
        );

        final metadata = h.soap.lastMetadata!;
        expect(metadata.title, '제목');
        expect(metadata.artist, '가수 이름');
        expect(metadata.album, '앨범 이름');
        expect(metadata.albumArtUri, 'https://resources.example.test/cover.jpg');
        expect(metadata.durationSeconds, 205);
        expect(metadata.mimeType, 'audio/flac');
      });
    });

    test('[DB-10] 스피커가 재생 명령을 거부하면 기기 이름이 든 DLNA_PLAY_FAILED 예외를 던지고 폴링하지 않는다', () {
      withHarness((async, h) {
        h.soap.commandResults['Play'] = false;

        final result = h.play(async, testTrack('101'));

        expect(result.errorCode, 'DLNA_PLAY_FAILED');
        expect((result.error! as PlaybackException).message, contains(h.device.friendlyName));
        // 곡 시작 알림은 스피커 명령 전에 이미 나간다. 재생 상태 알림은 나가지 않는다.
        expect(h.described, ['started(101)']);
        expect(h.channel.callsOf('setStreamingLock'), isEmpty);

        h.poll(async, 3);
        expect(h.soap.countOf('GetTransportInfo'), 0);
      });
    });

    test('[DB-11] 시작 위치가 있으면 재생 명령 뒤에 그 위치로 탐색한다', () {
      withHarness((async, h) {
        h.play(async, testTrack('101'), startPosition: const Duration(seconds: 30));

        expect(h.soap.actions, ['Stop', 'SetAVTransportURI', 'Play', 'Seek']);
        expect(h.soap.lastRelTime, '00:00:30');
      });
    });

    test('[DB-12] DASH 스트림은 시작 위치가 있어도 Seek를 보내지 않고, 등록할 때 startPositionMs로 넘긴다', () {
      // DB-12(dash-seek): SOAP Seek 없음. 30초 → startPositionMs 30000.
      withHarness((async, h) {
        h.api.defaultPlaybackInfo = dashStream();

        h.play(async, testTrack('101'), startPosition: const Duration(seconds: 30));

        expect(h.soap.actions, ['Stop', 'SetAVTransportURI', 'Play']);
        expect(h.channel.argumentsOf('registerTrackStream').single['startPositionMs'], 30000);
      });
    });

    test('[DB-13] 탐색 가능 여부는 처음에도, DASH 곡을 보낸 뒤에도, 단일 파일 곡을 보낸 뒤에도 가능이다', () {
      // DB-13(dash-seek): 항상 true.
      withHarness((async, h) {
        expect(h.backend.canSeek, isTrue);

        h.api.playbackInfos['101'] = dashStream();
        h.play(async, testTrack('101'));
        expect(h.backend.canSeek, isTrue);

        h.play(async, testTrack('102'));
        expect(h.backend.canSeek, isTrue);
      });
    });

    test('[DB-14] 진행 중에 요청이 취소되면 예외 없이 끝나고 그 뒤 단계를 실행하지 않는다', () {
      // 취소 여부는 다섯 곳에서 확인한다: 토큰 조회 뒤, 스트림 조회 뒤, 스피커 명령 차례가 왔을 때,
      // 프록시 등록 뒤, 재생 명령 뒤. checkpoint번째 확인에서 취소된 것으로 답한다.
      for (var checkpoint = 1; checkpoint <= 5; checkpoint++) {
        withHarness((async, h) {
          var asked = 0;

          final result = h.play(async, testTrack('101'), isCancelled: () => ++asked >= checkpoint);

          final reason = '$checkpoint번째 확인에서 취소';
          expect(result.error, isNull, reason: reason);
          expect(result.completed, isTrue, reason: reason);
          expect(h.api.calls, checkpoint >= 2 ? hasLength(1) : isEmpty, reason: reason);
          expect(h.channel.callsOf('registerTrackStream'), checkpoint >= 4 ? hasLength(1) : isEmpty, reason: reason);
          expect(h.described, checkpoint >= 5 ? ['started(101)'] : isEmpty, reason: reason);
          expect(h.soap.actions, checkpoint >= 5 ? ['Stop', 'SetAVTransportURI', 'Play'] : isEmpty, reason: reason);
          expect(h.channel.callsOf('setStreamingLock'), isEmpty, reason: reason);

          h.poll(async, 2);
          expect(h.soap.countOf('GetTransportInfo'), 0, reason: reason);
        });
      }
    });

    test('[DB-15] 연달아 재생을 요청하면 두 번째의 스피커 명령은 첫 번째가 끝난 뒤에 시작한다', () {
      withHarness((async, h) {
        h.soap.hold('SetAVTransportURI');
        final first = h.play(async, testTrack('101'));
        final second = h.play(async, testTrack('102'));

        // 첫 번째가 SetAVTransportURI에서 멈춰 있는 동안 두 번째는 프록시 등록도 시작하지 않는다.
        expect(first.completed, isFalse);
        expect(second.completed, isFalse);
        expect(h.channel.argumentsOf('registerTrackStream').map((a) => a['trackId']), ['101']);
        expect(h.soap.actions, ['Stop', 'SetAVTransportURI']);

        h.soap.release('SetAVTransportURI');
        async.flushMicrotasks();

        expect(first.completed, isTrue);
        expect(second.completed, isTrue);
        expect(h.channel.argumentsOf('registerTrackStream').map((a) => a['trackId']), ['101', '102']);
        expect(h.soap.actions, ['Stop', 'SetAVTransportURI', 'Play', 'Stop', 'SetAVTransportURI', 'Play']);
        expect(h.soap.lastStreamUrl, proxyUrlFor('102'));
      });
    });

    test('[DB-15] 앞의 요청이 실패해도 뒤의 요청은 실행된다', () {
      withHarness((async, h) {
        h.channel.responses['registerTrackStream'] = (call) {
          final id = (call.arguments as Map)['trackId'] as String;
          return id == '101' ? <String, Object?>{} : {'proxyUrl': proxyUrlFor(id)};
        };

        final first = capture(h.backend.play(testTrack('101'), isCancelled: () => false));
        final second = capture(h.backend.play(testTrack('102'), isCancelled: () => false));
        async.flushMicrotasks();

        expect(first.errorCode, 'PROXY_FAILED');
        expect(second.error, isNull);
        expect(second.completed, isTrue);
        expect(h.soap.lastStreamUrl, proxyUrlFor('102'));
      });
    });
  });

  group('폴링', () {
    test('[DB-16] 재생에 성공하면 1초마다 전송 상태와 위치를 한 번씩 읽는다', () {
      withHarness((async, h) {
        startPlaying(async, h);

        h.poll(async, 3);

        expect(h.soap.countOf('GetTransportInfo'), 3);
        expect(h.soap.countOf('GetPositionInfo'), 3);
      });
    });

    test('[DB-17] 위치를 알리고, 길이는 렌더러가 알려준 값을 쓴다', () {
      withHarness((async, h) {
        startPlaying(async, h, durationSeconds: 180);
        respond(h, state: 'PLAYING', rel: 12, duration: 200);

        h.poll(async);

        expect(h.described, ['position(12/200)', 'state(playing)']);
      });
    });

    test('[DB-17] 렌더러가 길이를 알려주지 않으면 곡의 길이를 쓴다', () {
      withHarness((async, h) {
        startPlaying(async, h, durationSeconds: 180);
        respond(h, state: 'PLAYING', rel: 12, duration: 0);

        h.poll(async);

        expect(h.described, ['position(12/180)', 'state(playing)']);
      });
    });

    test('[DB-18, DB-19, DB-20] PLAYING은 재생 중, TRANSITIONING은 버퍼링, PAUSED_PLAYBACK은 정지로 알린다', () {
      withHarness((async, h) {
        startPlaying(async, h);
        respond(h, state: 'PLAYING');
        respond(h, state: 'TRANSITIONING');
        respond(h, state: 'PAUSED_PLAYBACK');

        h.poll(async, 3);

        expect(h.described, ['state(playing)', 'state(playing,buffering)', 'state(stopped)']);
      });
    });

    test('[DB-21] 모르는 상태 이름이거나 상태만 응답이 없으면 상태는 알리지 않는다', () {
      withHarness((async, h) {
        startPlaying(async, h);
        respond(h, state: 'RECORDING', rel: 5);
        respond(h, state: null, rel: 6);

        h.poll(async, 2);

        expect(h.described, ['position(5/180)', 'position(6/180)']);
      });
    });

    test('[DB-22] PLAYING을 보기 전의 STOPPED·NO_MEDIA_PRESENT는 무시하고 폴링을 계속한다', () {
      withHarness((async, h) {
        startPlaying(async, h);
        respond(h, state: 'STOPPED', rel: 0);
        respond(h, state: 'NO_MEDIA_PRESENT', rel: 0);
        respond(h, state: 'PLAYING', rel: 1);

        h.poll(async, 3);

        expect(h.described, ['position(0/180)', 'position(0/180)', 'position(1/180)', 'state(playing)']);
        expect(h.soap.countOf('GetTransportInfo'), 3);
      });
    });

    test('[DB-23, DB-26] 끝 근처에서 재생하다 멈추면 곡 종료를 한 번 알리고 폴링을 멈춘다', () {
      withHarness((async, h) {
        startPlaying(async, h, durationSeconds: 180);
        respond(h, state: 'PLAYING', rel: 178);
        // 멈춘 시점에 렌더러가 위치 0을 알려도 직전 위치(178초)로 판정한다.
        respond(h, state: 'STOPPED', rel: 0);

        h.poll(async, 2);
        expect(h.described, ['position(178/180)', 'state(playing)', 'position(0/180)', 'ended(101)']);

        h.poll(async, 3);
        expect(h.soap.countOf('GetTransportInfo'), 2);
        expect(h.described.where((e) => e == 'ended(101)'), hasLength(1));
      });
    });

    test('[DB-23] NO_MEDIA_PRESENT도 STOPPED와 같이 곡 종료로 판정한다', () {
      withHarness((async, h) {
        startPlaying(async, h, durationSeconds: 180);
        respond(h, state: 'PLAYING', rel: 179);
        respond(h, state: 'NO_MEDIA_PRESENT');

        h.poll(async, 2);

        expect(h.described.last, 'ended(101)');
      });
    });

    test('[DB-23, DB-25] 곡 끝 3초 전부터는 곡 종료, 그보다 앞이면 스피커 쪽 정지로 본다', () {
      withHarness((async, h) {
        startPlaying(async, h, durationSeconds: 180);
        respond(h, state: 'PLAYING', rel: 177);
        respond(h, state: 'STOPPED');
        h.poll(async, 2);
        expect(h.described.last, 'ended(101)');
      });
      withHarness((async, h) {
        startPlaying(async, h, durationSeconds: 180);
        respond(h, state: 'PLAYING', rel: 176);
        respond(h, state: 'STOPPED');
        h.poll(async, 2);
        expect(h.described.last, 'state(stopped)');
        expect(h.described, isNot(contains('ended(101)')));

        h.poll(async, 3);
        expect(h.soap.countOf('GetTransportInfo'), 2);
      });
    });

    test('[DB-24] 길이를 모르는 곡은 재생하다 멈추면 위치와 상관없이 곡 종료로 본다', () {
      withHarness((async, h) {
        startPlaying(async, h, durationSeconds: 0);
        respond(h, state: 'PLAYING', rel: 5);
        respond(h, state: 'STOPPED', rel: 0);

        h.poll(async, 2);

        expect(h.described, ['position(5/-)', 'state(playing)', 'position(0/-)', 'ended(101)']);
      });
    });

    test('[DB-27] 응답이 3회 연속 없으면 폴링을 멈추고 정지와 DLNA_UNREACHABLE을 알린다', () {
      withHarness((async, h) {
        startPlaying(async, h);
        h.soap
          ..transportState = null
          ..positionInfo = null;

        h.poll(async, 2);
        expect(h.events, isEmpty);

        h.poll(async);
        expect(h.described, ['state(stopped)', 'error(DLNA_UNREACHABLE)']);

        h.poll(async, 3);
        expect(h.soap.countOf('GetTransportInfo'), 3);
      });
    });

    test('[DB-28] 무응답이 이어지다 정상 응답이 오면 횟수를 다시 센다', () {
      withHarness((async, h) {
        startPlaying(async, h);
        respond(h);
        respond(h);
        respond(h, state: 'PLAYING', rel: 3);
        respond(h);
        respond(h);

        h.poll(async, 5);
        expect(h.described, ['position(3/180)', 'state(playing)']);

        respond(h);
        h.poll(async);
        expect(h.described.last, 'error(DLNA_UNREACHABLE)');
      });
    });

    test('[DB-29] 응답을 기다리는 사이 정지하면 늦게 온 응답을 버린다', () {
      withHarness((async, h) {
        startPlaying(async, h);
        h.soap.hold('GetTransportInfo');
        h.poll(async);

        h.backend.stop();
        async.flushMicrotasks();
        h.events.clear();
        h.soap.release('GetTransportInfo');
        async.flushMicrotasks();

        expect(h.events, isEmpty);
      });
    });

    test('[DB-29] 응답을 기다리는 사이 다른 곡을 재생하면 늦게 온 응답을 버린다', () {
      withHarness((async, h) {
        startPlaying(async, h);
        respond(h, state: 'PLAYING', rel: 99);
        h.soap.hold('GetTransportInfo');
        h.poll(async);

        h.play(async, testTrack('102'));
        h.events.clear();
        h.soap.release('GetTransportInfo');
        async.flushMicrotasks();

        expect(h.events, isEmpty);
      });
    });

    test('[DB-30] 앞의 확인이 끝나지 않았으면 다음 차례는 건너뛴다', () {
      withHarness((async, h) {
        startPlaying(async, h);
        h.soap.hold('GetTransportInfo');

        h.poll(async, 3);
        expect(h.soap.countOf('GetTransportInfo'), 1);
        expect(h.soap.countOf('GetPositionInfo'), 1);

        h.soap.release('GetTransportInfo');
        async.flushMicrotasks();
        h.poll(async);
        expect(h.soap.countOf('GetTransportInfo'), 2);
      });
    });

    test('[DB-31] 폴링이 멈추면(정지, 곡 끝, 무응답, 새 재생) 스트리밍 잠금을 푼다', () {
      withHarness((async, h) {
        startPlaying(async, h);
        h.backend.stop();
        async.flushMicrotasks();
        expect(lastStreamingLock(h), isFalse, reason: '정지');
      });
      withHarness((async, h) {
        startPlaying(async, h);
        respond(h, state: 'PLAYING', rel: 179);
        respond(h, state: 'STOPPED');
        h.poll(async, 2);
        expect(lastStreamingLock(h), isFalse, reason: '곡 끝');
      });
      withHarness((async, h) {
        startPlaying(async, h);
        h.soap
          ..transportState = null
          ..positionInfo = null;
        h.poll(async, 3);
        expect(lastStreamingLock(h), isFalse, reason: '무응답');
      });
      withHarness((async, h) {
        startPlaying(async, h);
        h.api.defaultPlaybackInfo = null;
        h.play(async, testTrack('102'));
        expect(lastStreamingLock(h), isFalse, reason: '새 재생');
      });
    });
  });

  group('갭리스', () {
    /// 다음 곡 등록을 요청하고 끝까지 진행시킨다.
    void setNext(FakeAsync async, DlnaBackendHarness h, String? id, {int durationSeconds = 240}) =>
        registerNext(async, h, id, durationSeconds: durationSeconds);

    test('[DB-32] 다음 곡을 조회해 프록시에 등록하고 스피커에 SetNextAVTransportURI를 보낸다', () {
      withHarness((async, h) {
        startPlaying(async, h);

        setNext(async, h, '102');

        expect(h.api.calls, ['getPlaybackInfo:102:LOSSLESS']);
        expect(h.channel.argumentsOf('registerTrackStream').single['trackId'], '102');
        expect(h.soap.actions, ['SetNextAVTransportURI']);
        expect(h.soap.lastNextStreamUrl, proxyUrlFor('102'));
        expect(h.soap.lastNextMetadata!.title, '곡 102');
        expect(h.soap.lastNextMetadata!.durationSeconds, 240);
      });
    });

    test('[DB-33] 이미 등록한 곡을 다시 요청하면 아무것도 하지 않는다', () {
      withHarness((async, h) {
        startPlaying(async, h);
        setNext(async, h, '102');
        h.clearRecords();

        setNext(async, h, '102');

        expect(h.api.calls, isEmpty);
        expect(h.soap.calls, isEmpty);
      });
    });

    test('[DB-34] 다음 곡이 없어지면 빈 주소로 스피커의 등록을 지운다', () {
      withHarness((async, h) {
        startPlaying(async, h);
        setNext(async, h, '102');
        h.clearRecords();

        setNext(async, h, null);

        expect(h.soap.actions, ['SetNextAVTransportURI']);
        expect(h.soap.lastNextStreamUrl, '');
        expect(h.soap.lastNextMetadata, isNull);
      });
    });

    test('[DB-35] 등록한 곡이 없으면 지우는 요청을 보내지 않는다', () {
      withHarness((async, h) {
        startPlaying(async, h);

        setNext(async, h, null);

        expect(h.soap.calls, isEmpty);
      });
    });

    test('[DB-36] 폰 스피커가 선택되어 있으면 다음 곡을 등록하지 않는다', () {
      withHarness((async, h) {
        h.manager.selectedDeviceNotifier.value = DlnaDevice.localSpeaker;

        setNext(async, h, '102');

        expect(h.api.calls, isEmpty);
        expect(h.soap.calls, isEmpty);
      });
    });

    test('[DB-37] 스피커가 다음 곡 등록을 거부하면 그 스피커에는 다시 시도하지 않는다', () {
      withHarness((async, h) {
        startPlaying(async, h);
        h.soap.commandResults['SetNextAVTransportURI'] = false;
        setNext(async, h, '102');
        expect(h.soap.actions, ['SetNextAVTransportURI']);
        h.clearRecords();

        h.soap.commandResults['SetNextAVTransportURI'] = true;
        setNext(async, h, '103');
        setNext(async, h, null);

        expect(h.api.calls, isEmpty);
        expect(h.soap.calls, isEmpty);
      });
    });

    test('[DB-38] 다음 곡의 스트림 정보나 프록시 주소를 받지 못하면 등록하지 않는다', () {
      withHarness((async, h) {
        startPlaying(async, h);
        h.api.playbackInfos['102'] = null;
        setNext(async, h, '102');
        expect(h.channel.callsOf('registerTrackStream'), isEmpty);
        expect(h.soap.calls, isEmpty);

        h.channel.failing.add('registerTrackStream');
        setNext(async, h, '103');
        expect(h.soap.calls, isEmpty);
      });
    });

    test('[DB-38] 준비하는 사이 선택한 스피커가 바뀌면 등록하지 않는다', () {
      withHarness((async, h) {
        startPlaying(async, h);
        h.channel.hold('registerTrackStream');
        setNext(async, h, '102');

        h.manager.selectedDeviceNotifier.value = remoteSpeaker(udn: 'uuid:speaker-2', host: '192.0.2.11');
        h.channel.release('registerTrackStream');
        async.flushMicrotasks();

        expect(h.soap.calls, isEmpty);
      });
    });

    test('[DB-39] 스피커가 등록해 둔 다음 곡을 재생하기 시작하면 그 곡의 시작으로 알리고 기준을 새 곡으로 바꾼다', () {
      withHarness((async, h) {
        startPlaying(async, h, durationSeconds: 180);
        h.api.playbackInfos['102'] = dashStream();
        setNext(async, h, '102', durationSeconds: 240);
        h.clearRecords();
        expect(h.backend.canSeek, isTrue);

        // 렌더러가 호스트 표기를 바꿔 돌려줘도 같은 곡으로 알아본다.
        final reported = proxyUrlFor('102').replaceFirst('192.0.2.1:8765', 'phone.test:8765');
        respond(h, state: 'PLAYING', rel: 1, trackUri: reported);
        h.poll(async);

        // 넘어간 차례에는 곡 시작만 알린다.
        expect(h.described, ['started(102)']);
        final started = h.events.single as BackendTrackStarted;
        expect(started.duration, const Duration(seconds: 240));
        expect(started.quality!.audioQuality, 'HI_RES_LOSSLESS');
        // DB-39(dash-seek): 새 곡이 DASH여도 탐색 가능은 그대로다.
        expect(h.backend.canSeek, isTrue);

        respond(h, state: 'PLAYING', rel: 239, trackUri: reported);
        respond(h, state: 'STOPPED', trackUri: reported);
        h.poll(async, 2);
        expect(h.described.sublist(1), ['position(239/240)', 'state(playing)', 'ended(102)']);
      });
    });

    test('[DB-40] 재생 중인 주소가 비어 있거나, 지금 곡이거나, 등록한 곡이 아니면 넘어간 것으로 보지 않는다', () {
      withHarness((async, h) {
        startPlaying(async, h);
        setNext(async, h, '102');
        h.clearRecords();
        respond(h, state: 'PLAYING', rel: 1, trackUri: '');
        respond(h, state: 'PLAYING', rel: 2, trackUri: proxyUrlFor('101'));
        respond(h, state: 'PLAYING', rel: 3, trackUri: proxyUrlFor('999'));

        h.poll(async, 3);

        expect(h.described, isNot(contains('started(102)')));
        expect(h.described.where((e) => e.startsWith('position')), hasLength(3));
      });
    });

    test('[DB-41] 새로 재생을 요청하면 등록 정보가 지워져 이후 주소가 바뀌어도 넘어간 것으로 보지 않는다', () {
      withHarness((async, h) {
        startPlaying(async, h);
        setNext(async, h, '102');
        h.play(async, testTrack('103'));
        h.clearRecords();
        respond(h, state: 'PLAYING', rel: 1, trackUri: proxyUrlFor('102'));

        h.poll(async);

        expect(h.described, ['position(1/180)', 'state(playing)']);
      });
    });

    test('[DB-42] 다음 곡 등록은 진행 중인 재생 명령이 끝난 뒤에 실행된다', () {
      withHarness((async, h) {
        h.soap.hold('SetAVTransportURI');
        h.play(async, testTrack('101'));
        setNext(async, h, '102');

        expect(h.api.calls, ['getPlaybackInfo:101:LOSSLESS']);

        h.soap.release('SetAVTransportURI');
        async.flushMicrotasks();

        expect(h.soap.actions, ['Stop', 'SetAVTransportURI', 'Play', 'SetNextAVTransportURI']);
      });
    });
  });

  group('그 밖의 명령', () {
    test('[DB-43] 일시정지는 Pause를 보내고 정지를 알린다', () {
      withHarness((async, h) {
        final result = capture(h.backend.pause());
        async.flushMicrotasks();

        expect(result.error, isNull);
        expect(h.soap.actions, ['Pause']);
        expect(h.described, ['state(stopped)']);
      });
    });

    test('[DB-43] 일시정지가 거부되면 DLNA_PAUSE_FAILED 예외를 던지고 상태를 알리지 않는다', () {
      withHarness((async, h) {
        h.soap.commandResults['Pause'] = false;

        final result = capture(h.backend.pause());
        async.flushMicrotasks();

        expect(result.errorCode, 'DLNA_PAUSE_FAILED');
        expect(h.events, isEmpty);
      });
    });

    test('[DB-44] 재개는 Play를 보내고 재생 중을 알린다', () {
      withHarness((async, h) {
        final result = capture(h.backend.resume());
        async.flushMicrotasks();

        expect(result.error, isNull);
        expect(h.soap.actions, ['Play']);
        expect(h.described, ['state(playing)']);
      });
    });

    test('[DB-44] 재개가 거부되면 DLNA_RESUME_FAILED 예외를 던지고 상태를 알리지 않는다', () {
      withHarness((async, h) {
        h.soap.commandResults['Play'] = false;

        final result = capture(h.backend.resume());
        async.flushMicrotasks();

        expect(result.errorCode, 'DLNA_RESUME_FAILED');
        expect(h.events, isEmpty);
      });
    });

    test('[DB-45] 단일 파일 곡의 탐색은 초 단위 위치로 Seek를 보내고, 거부되어도 예외를 던지지 않는다', () {
      // DB-45(dash-seek): 지금 곡이 단일 파일이면 그대로. 프록시에 다시 등록하지 않는다.
      withHarness((async, h) {
        startPlaying(async, h);
        h.soap.commandResults['Seek'] = false;

        final result = h.seek(async, const Duration(seconds: 42, milliseconds: 900));

        expect(result.error, isNull);
        expect(h.soap.actions, ['Seek']);
        expect(h.soap.lastRelTime, '00:00:42');
        expect(h.channel.callsOf('registerTrackStream'), isEmpty);
        expect(h.events, isEmpty);
      });
    });

    test('[DB-46] 정지는 폴링을 멈추고 Stop을 보낸 뒤 정지를 알린다', () {
      withHarness((async, h) {
        startPlaying(async, h);

        h.backend.stop();
        async.flushMicrotasks();

        expect(h.soap.actions, ['Stop']);
        expect(h.described, ['state(stopped)']);

        h.poll(async, 5);
        expect(h.soap.countOf('GetTransportInfo'), 0);
      });
    });

    test('[DB-47] dispose는 폴링을 멈추고 이벤트 스트림을 닫는다', () {
      withHarness((async, h) {
        startPlaying(async, h);
        var closed = false;
        h.backend.events.listen(null, onDone: () => closed = true);

        h.backend.dispose();
        async.flushMicrotasks();
        h.poll(async, 3);

        expect(closed, isTrue);
        expect(h.soap.countOf('GetTransportInfo'), 0);
      });
    });
  });

  group('시작 위치 (dash-seek)', () {
    test('[DB-50] DASH 곡은 시작 위치를 프록시 등록의 startPositionMs로 넘기고 Seek를 보내지 않는다', () {
      // DB-50: startPositionMs = P(밀리초). 30.5초 → 30500.
      withHarness((async, h) {
        h.api.defaultPlaybackInfo = dashStream(manifest: '<MPD id="m"/>');
        h.answerStartOffset(const Duration(seconds: 28));

        final result = h.play(async, testTrack('101'), startPosition: const Duration(seconds: 30, milliseconds: 500));

        expect(result.error, isNull);
        expect(h.channel.argumentsOf('registerTrackStream').single, {
          'trackId': '101',
          'directUrl': '',
          'manifestXml': '<MPD id="m"/>',
          'allowedHost': fakeSpeakerHost,
          'mimeType': 'audio/mp4',
          'startPositionMs': 30500,
        });
        expect(h.soap.actions, ['Stop', 'SetAVTransportURI', 'Play']);
        expect(h.soap.lastStreamUrl, proxyUrlAt('101', 30500));
        expect(h.described, ['started(101)', 'state(playing,buffering)']);
      });
    });

    test('[DB-50] 등록 응답의 startOffsetMs를 그 곡의 시작 오프셋으로 기억한다', () {
      // DB-50: 요청 30초, 응답 28초 → 스피커가 0을 알려 주는 동안 알리는 위치는 28초(요청값 30이 아님).
      withHarness((async, h) {
        h.api.defaultPlaybackInfo = dashStream();
        h.answerStartOffset(const Duration(seconds: 28));
        h.play(async, testTrack('101', durationSeconds: 180), startPosition: const Duration(seconds: 30));
        h.clearRecords();
        respond(h, state: 'PLAYING', rel: 0);

        h.poll(async);

        expect(h.described, ['position(28/180)', 'state(playing)']);
      });
    });

    test('[DB-50] DASH 곡을 처음부터 재생하면 startPositionMs는 0이고 시작 오프셋도 0이다', () {
      // DB-50, DB-17: 오프셋 0이면 위치·길이는 렌더러 값 그대로.
      withHarness((async, h) {
        h.api.defaultPlaybackInfo = dashStream();
        h.answerStartOffset(const Duration(seconds: 28));

        h.play(async, testTrack('101', durationSeconds: 180));

        expect(h.channel.argumentsOf('registerTrackStream').single['startPositionMs'], 0);
        expect(h.soap.actions, ['Stop', 'SetAVTransportURI', 'Play']);

        h.clearRecords();
        respond(h, state: 'PLAYING', rel: 12, duration: 200);
        h.poll(async);
        expect(h.described, ['position(12/200)', 'state(playing)']);
      });
    });

    test('[DB-50b] 단일 파일 곡은 startPositionMs를 0으로 보내고 재생 명령 뒤에 Seek를 보낸다', () {
      // DB-50b: 단일 파일은 등록에 시작 위치를 넘기지 않는다. 시작 오프셋 0(위치 보정 없음).
      withHarness((async, h) {
        h.answerStartOffset(const Duration(seconds: 28));

        h.play(async, testTrack('101', durationSeconds: 180), startPosition: const Duration(seconds: 30));

        expect(h.channel.argumentsOf('registerTrackStream').single['startPositionMs'], 0);
        expect(h.soap.actions, ['Stop', 'SetAVTransportURI', 'Play', 'Seek']);
        expect(h.soap.lastRelTime, '00:00:30');
        expect(h.soap.lastStreamUrl, proxyUrlFor('101'));

        h.clearRecords();
        respond(h, state: 'PLAYING', rel: 31, duration: 200);
        h.poll(async);
        expect(h.described, ['position(31/200)', 'state(playing)']);
      });
    });
  });

  group('DASH 곡의 탐색 (dash-seek)', () {
    test('[DB-51] DASH 곡의 탐색은 같은 곡을 그 위치로 다시 등록한 뒤 새 주소로 재생 명령을 보낸다', () {
      // DB-51: (1) registerTrackStream (2) Stop · SetAVTransportURI · Play. SOAP Seek 없음.
      withHarness((async, h) {
        startDash(async, h, manifest: '<MPD id="m"/>');
        h.answerStartOffset(const Duration(seconds: 40));
        h.soap.lastMetadata = null;
        h.channel.hold('registerTrackStream');

        final result = capture(h.backend.seek(const Duration(seconds: 42, milliseconds: 900)));
        async.flushMicrotasks();

        // 등록 응답을 기다리는 동안에는 스피커에 아무것도 보내지 않는다.
        expect(h.channel.argumentsOf('registerTrackStream'), [
          {
            'trackId': '101',
            'directUrl': '',
            'manifestXml': '<MPD id="m"/>',
            'allowedHost': fakeSpeakerHost,
            'mimeType': 'audio/mp4',
            'startPositionMs': 42900,
          },
        ]);
        expect(h.soap.calls, isEmpty);

        h.channel.release('registerTrackStream');
        async.flushMicrotasks();

        expect(result.error, isNull);
        expect(result.completed, isTrue);
        expect(h.soap.actions, ['Stop', 'SetAVTransportURI', 'Play']);
        expect(h.soap.lastStreamUrl, proxyUrlAt('101', 42900));
      });
    });

    test('[DB-51] 탐색의 재생 명령에는 재생을 시작할 때와 같은 메타데이터를 보낸다', () {
      // DB-51: play 와 같은 메타데이터(DB-09).
      withHarness((async, h) {
        h.api.defaultPlaybackInfo = dashStream();
        h.play(
          async,
          testTrack(
            '101',
            title: '제목',
            artistName: '가수 이름',
            albumTitle: '앨범 이름',
            coverUrl: 'https://resources.example.test/cover.jpg',
            durationSeconds: 205,
          ),
        );
        h.answerStartOffset(const Duration(seconds: 40));
        h.soap.lastMetadata = null;

        h.seek(async, const Duration(seconds: 42));

        expect(h.soap.lastMetadata, isNotNull);
        final metadata = h.soap.lastMetadata!;
        expect(metadata.title, '제목');
        expect(metadata.artist, '가수 이름');
        expect(metadata.album, '앨범 이름');
        expect(metadata.albumArtUri, 'https://resources.example.test/cover.jpg');
        expect(metadata.durationSeconds, 205);
        expect(metadata.mimeType, 'audio/mp4');
      });
    });

    test('[DB-51] 탐색은 TIDAL API를 다시 부르지 않고 재생을 시작할 때 받은 스트림 정보를 쓴다', () {
      // DB-51: 그 사이 API가 다른 매니페스트를 주게 되어도 처음 받은 것으로 등록한다.
      withHarness((async, h) {
        startDash(async, h, manifest: '<MPD id="first"/>');
        h.api.playbackInfos['101'] = dashStream(manifest: '<MPD id="later"/>');
        h.answerStartOffset(const Duration(seconds: 40));

        h.seek(async, const Duration(seconds: 42));

        expect(h.api.calls, isEmpty);
        expect(h.channel.argumentsOf('registerTrackStream').map((a) => a['manifestXml']), ['<MPD id="first"/>']);
      });
    });

    test('[DB-51, DB-39] 갭리스로 넘어간 곡이 DASH면 탐색은 그 곡을 다시 등록한다', () {
      // DB-51: "지금 곡" 은 넘어간 뒤의 곡이다. 스트림 정보는 다음 곡으로 등록할 때 받은 것.
      withHarness((async, h) {
        startPlaying(async, h);
        h.api.playbackInfos['102'] = dashStream(manifest: '<MPD id="next"/>');
        registerNext(async, h, '102', durationSeconds: 240);
        respond(h, state: 'PLAYING', rel: 1, trackUri: proxyUrlFor('102'));
        h.poll(async);
        h.answerStartOffset(const Duration(seconds: 60));
        h.clearRecords();
        h.soap.lastMetadata = null;

        h.seek(async, const Duration(seconds: 61));

        expect(h.channel.argumentsOf('registerTrackStream'), hasLength(1));
        final args = h.channel.argumentsOf('registerTrackStream').single;
        expect(args['trackId'], '102');
        expect(args['manifestXml'], '<MPD id="next"/>');
        expect(args['startPositionMs'], 61000);
        expect(h.api.calls, isEmpty);
        expect(h.soap.actions, ['Stop', 'SetAVTransportURI', 'Play']);
        expect(h.soap.lastStreamUrl, proxyUrlAt('102', 61000));
        expect(h.soap.lastMetadata!.title, '곡 102');
        expect(h.described, ['position(60/240)', 'state(playing,buffering)']);
      });
    });

    test('[DB-45, DB-39] 갭리스로 넘어간 곡이 단일 파일이면 탐색은 Seek만 보낸다', () {
      // DB-45: 지금 곡이 단일 파일이면 그대로(앞 곡이 DASH였어도).
      withHarness((async, h) {
        startDash(async, h);
        registerNext(async, h, '102');
        respond(h, state: 'PLAYING', rel: 1, trackUri: proxyUrlFor('102'));
        h.poll(async);
        h.clearRecords();

        final result = h.seek(async, const Duration(seconds: 42));

        expect(result.error, isNull);
        expect(h.soap.actions, ['Seek']);
        expect(h.soap.lastRelTime, '00:00:42');
        expect(h.channel.callsOf('registerTrackStream'), isEmpty);
      });
    });

    test('[DB-52] 탐색에 성공하면 곧바로 시작 오프셋 위치와 버퍼링을 알리고, 곡 시작은 다시 알리지 않는다', () {
      // DB-52: BackendPositionChanged(시작 오프셋, duration: 곡의 길이) → BackendStateChanged(playing, buffering).
      withHarness((async, h) {
        startDash(async, h, durationSeconds: 180);
        h.answerStartOffset(const Duration(seconds: 40));

        final result = h.seek(async, const Duration(seconds: 42, milliseconds: 900));

        expect(result.error, isNull);
        expect(h.described, ['position(40/180)', 'state(playing,buffering)']);
        final position = h.events.first as BackendPositionChanged;
        expect(position.position, const Duration(seconds: 40));
        expect(position.duration, const Duration(seconds: 180));
        expect(lastStreamingLock(h) ?? true, isTrue);
      });
    });

    test('[DB-52] 탐색 뒤의 폴링은 응답의 startOffsetMs를 시작 오프셋으로 쓴다', () {
      // DB-52: 시작 오프셋이 응답값(40초)이 된다(요청값 42초가 아님). DB-55c 로 관찰.
      withHarness((async, h) {
        startDash(async, h, durationSeconds: 180);
        h.answerStartOffset(const Duration(seconds: 40));
        h.seek(async, const Duration(seconds: 42));
        h.clearRecords();
        respond(h, state: 'PLAYING', rel: 0);

        h.poll(async);

        expect(h.described, ['position(40/180)', 'state(playing)']);
        expect(h.soap.countOf('GetTransportInfo'), 1);
      });
    });

    test('[DB-52] 탐색 뒤에는 PLAYING을 아직 보지 못한 상태로 돌아간다', () {
      // DB-52, DB-22: 탐색 전에 PLAYING 을 봤어도, 탐색 뒤 PLAYING 전의 STOPPED 는 무시하고 폴링을 계속한다.
      withHarness((async, h) {
        startDash(async, h, durationSeconds: 180);
        respond(h, state: 'PLAYING', rel: 5);
        h.poll(async);
        h.answerStartOffset(const Duration(seconds: 60));
        h.seek(async, const Duration(seconds: 60));
        h.clearRecords();
        respond(h, state: 'STOPPED', rel: 0);
        respond(h, state: 'PLAYING', rel: 1);

        h.poll(async, 2);

        expect(h.described, ['position(60/180)', 'position(61/180)', 'state(playing)']);
        expect(h.soap.countOf('GetTransportInfo'), 2);
      });
    });

    test('[DB-52] 탐색 뒤에는 무응답 횟수를 0부터 다시 센다', () {
      // DB-52, DB-27: 탐색 전 2회 무응답 + 탐색 뒤 2회 무응답으로는 끊기지 않고, 탐색 뒤 3회째에 끊긴다.
      withHarness((async, h) {
        startDash(async, h);
        respond(h);
        respond(h);
        h.poll(async, 2);
        h.answerStartOffset(const Duration(seconds: 60));
        h.seek(async, const Duration(seconds: 60));
        h.clearRecords();
        respond(h);
        respond(h);
        respond(h);

        h.poll(async, 2);
        expect(h.events, isEmpty);

        h.poll(async);
        expect(h.described, ['state(stopped)', 'error(DLNA_UNREACHABLE)']);
      });
    });

    test('[DB-52] 탐색 뒤의 마지막 위치는 시작 오프셋이다', () {
      // DB-52, DB-23, DB-25: 스피커가 0만 알려 주다 멈추면 시작 오프셋으로 곡 끝을 판정한다.
      withHarness((async, h) {
        // 끝 근처(178초)로 탐색 → 탐색 전 위치(5초)가 아니라 178초로 판정해 곡 종료.
        startDash(async, h, durationSeconds: 180);
        respond(h, state: 'PLAYING', rel: 5);
        h.poll(async);
        h.answerStartOffset(const Duration(seconds: 178));
        h.seek(async, const Duration(seconds: 179));
        h.clearRecords();
        respond(h, state: 'PLAYING', rel: 0);
        respond(h, state: 'STOPPED', rel: 0);

        h.poll(async, 2);

        expect(h.described, ['position(178/180)', 'state(playing)', 'position(178/180)', 'ended(101)']);
      });
      withHarness((async, h) {
        // 끝 근처(178초)에서 앞(30초)으로 탐색 → 탐색 전 위치가 아니라 30초로 판정해 스피커 쪽 정지.
        startDash(async, h, durationSeconds: 180);
        respond(h, state: 'PLAYING', rel: 178);
        h.poll(async);
        h.answerStartOffset(const Duration(seconds: 30));
        h.seek(async, const Duration(seconds: 31));
        h.clearRecords();
        respond(h, state: 'PLAYING', rel: 0);
        respond(h, state: 'STOPPED', rel: 0);

        h.poll(async, 2);

        expect(h.described, ['position(30/180)', 'state(playing)', 'position(30/180)', 'state(stopped)']);
      });
    });

    test('[DB-52] 탐색 뒤에는 위치 기준을 다시 정한다', () {
      // DB-52, DB-54: 앞 흐름에서 절대로 정했어도 탐색 뒤의 첫 RelTime(5 < 60 − 2)으로 다시 판정 → 상대.
      withHarness((async, h) {
        startDashAt(async, h, offsetSeconds: 60);
        respond(h, state: 'PLAYING', rel: 60);
        h.poll(async);
        expect(h.described, ['position(60/180)', 'state(playing)']);

        h.seek(async, const Duration(seconds: 60));
        h.clearRecords();
        respond(h, state: 'PLAYING', rel: 5);
        h.poll(async);

        expect(h.described, ['position(65/180)', 'state(playing)']);
      });
    });

    test('[DB-53] 탐색의 프록시 등록이 실패하면 PROXY_FAILED 예외를 던지고 스피커 명령·시작 오프셋·폴링은 그대로다', () {
      // DB-53: 스피커에 명령 없음. 시작 오프셋 28초와 폴링이 유지된다.
      withHarness((async, h) {
        startDashAt(async, h, offsetSeconds: 28);
        h.channel.failing.add('registerTrackStream');

        final result = h.seek(async, const Duration(seconds: 90));

        expect(result.errorCode, 'PROXY_FAILED');
        expect(h.soap.calls, isEmpty);
        expect(h.events, isEmpty);

        respond(h, state: 'PLAYING', rel: 0);
        h.poll(async);
        expect(h.soap.countOf('GetTransportInfo'), 1);
        expect(h.described, ['position(28/180)', 'state(playing)']);
      });
    });

    test('[DB-53] 탐색의 등록 응답에 주소가 없어도 PROXY_FAILED 예외를 던진다', () {
      // DB-53: 프록시 주소가 빈 값(NB-03).
      withHarness((async, h) {
        startDash(async, h);
        h.channel.responses['registerTrackStream'] = (_) => <String, Object?>{'startOffsetMs': 88000};

        final result = h.seek(async, const Duration(seconds: 90));

        expect(result.errorCode, 'PROXY_FAILED');
        expect(h.soap.calls, isEmpty);
        expect(h.events, isEmpty);
      });
    });

    test('[DB-53b] 탐색의 재생 명령이 거부되면 기기 이름이 든 DLNA_PLAY_FAILED 예외를 던지고 시작 오프셋은 그대로다', () {
      // DB-53b: 새 오프셋(88초)을 쓰지 않는다. 폴링 유지 여부는 규칙에 없으므로, 위치를 알린다면 28초여야 한다.
      withHarness((async, h) {
        startDashAt(async, h, offsetSeconds: 28);
        h.answerStartOffset(const Duration(seconds: 88));
        h.soap.commandResults['Play'] = false;

        final result = h.seek(async, const Duration(seconds: 90));

        expect(result.errorCode, 'DLNA_PLAY_FAILED');
        expect((result.error! as PlaybackException).message, contains(h.device.friendlyName));
        expect(h.events, isEmpty);

        respond(h, state: 'PLAYING', rel: 0);
        h.poll(async);
        expect(h.described.where((e) => e.startsWith('position')), everyElement('position(28/180)'));
      });
    });

    test('[DB-57] 일시정지 상태에서 탐색하면 재생 명령 뒤에 Pause를 보내고 정지로 알린다', () {
      // DB-57: state(playing,buffering) 대신 state(stopped).
      withHarness((async, h) {
        startDash(async, h, durationSeconds: 180);
        capture(h.backend.pause());
        async.flushMicrotasks();
        h.answerStartOffset(const Duration(seconds: 60));
        h.clearRecords();

        final result = h.seek(async, const Duration(seconds: 61));

        expect(result.error, isNull);
        expect(h.soap.actions, ['Stop', 'SetAVTransportURI', 'Play', 'Pause']);
        expect(h.described, ['position(60/180)', 'state(stopped)']);
      });
    });

    test('[DB-57] 일시정지 뒤 재개했으면 탐색에 Pause를 보내지 않는다', () {
      // DB-57: resume() 이 일시정지 상태를 끝낸다.
      withHarness((async, h) {
        startDash(async, h, durationSeconds: 180);
        capture(h.backend.pause());
        async.flushMicrotasks();
        capture(h.backend.resume());
        async.flushMicrotasks();
        h.answerStartOffset(const Duration(seconds: 60));
        h.clearRecords();

        h.seek(async, const Duration(seconds: 61));

        expect(h.soap.actions, ['Stop', 'SetAVTransportURI', 'Play']);
        expect(h.described, ['position(60/180)', 'state(playing,buffering)']);
      });
    });

    test('[DB-57] 일시정지 뒤 새로 재생했으면 탐색에 Pause를 보내지 않는다', () {
      // DB-57: 새 play 가 일시정지 상태를 끝낸다.
      withHarness((async, h) {
        startDash(async, h);
        capture(h.backend.pause());
        async.flushMicrotasks();
        startDash(async, h, id: '102', durationSeconds: 180);
        h.answerStartOffset(const Duration(seconds: 60));

        h.seek(async, const Duration(seconds: 61));

        expect(h.soap.actions, ['Stop', 'SetAVTransportURI', 'Play']);
        expect(h.described, ['position(60/180)', 'state(playing,buffering)']);
      });
    });

    test('[DB-57] 일시정지가 거부됐으면 탐색에 Pause를 보내지 않는다', () {
      // DB-57: 일시정지 상태는 pause() 가 성공했을 때만이다.
      withHarness((async, h) {
        startDash(async, h, durationSeconds: 180);
        h.soap.commandResults['Pause'] = false;
        capture(h.backend.pause());
        async.flushMicrotasks();
        h.soap.commandResults.remove('Pause');
        h.answerStartOffset(const Duration(seconds: 60));
        h.clearRecords();

        h.seek(async, const Duration(seconds: 61));

        expect(h.soap.actions, ['Stop', 'SetAVTransportURI', 'Play']);
        expect(h.described, ['position(60/180)', 'state(playing,buffering)']);
      });
    });

    test('[DB-59] 다음 곡이 등록되어 있으면 탐색의 재생 명령 뒤에 같은 주소·메타데이터로 다시 등록한다', () {
      // DB-59: 프록시 등록과 스트림 조회는 다시 하지 않고 SetNextAVTransportURI 만 다시 보낸다. 이후 갭리스 전환은 그대로.
      withHarness((async, h) {
        startDash(async, h);
        registerNext(async, h, '102', durationSeconds: 240);
        h.answerStartOffset(const Duration(seconds: 60));
        h.clearRecords();
        h.soap
          ..lastNextStreamUrl = null
          ..lastNextMetadata = null;

        h.seek(async, const Duration(seconds: 61));

        expect(h.soap.actions, ['Stop', 'SetAVTransportURI', 'Play', 'SetNextAVTransportURI']);
        expect(h.soap.lastNextStreamUrl, proxyUrlFor('102'));
        expect(h.soap.lastNextMetadata!.title, '곡 102');
        expect(h.soap.lastNextMetadata!.durationSeconds, 240);
        expect(h.channel.argumentsOf('registerTrackStream').map((a) => a['trackId']), ['101']);
        expect(h.api.calls, isEmpty);

        h.clearRecords();
        respond(h, state: 'PLAYING', rel: 1, trackUri: proxyUrlFor('102'));
        h.poll(async);
        expect(h.described, ['started(102)']);
      });
    });

    test('[DB-59] 다음 곡을 다시 등록하지 못하면 등록 정보를 지우되 그 스피커를 갭리스 불가로 표시하지 않는다', () {
      // DB-59: 등록 정보가 지워져 DB-39 가 일어나지 않고, 이후 setNext 는 다시 시도된다(DB-37 과 다름).
      withHarness((async, h) {
        startDash(async, h);
        registerNext(async, h, '102');
        h.answerStartOffset(const Duration(seconds: 60));
        h.soap.commandResults['SetNextAVTransportURI'] = false;
        h.clearRecords();

        final result = h.seek(async, const Duration(seconds: 61));

        expect(result.error, isNull);
        expect(h.soap.actions, ['Stop', 'SetAVTransportURI', 'Play', 'SetNextAVTransportURI']);

        h.soap.commandResults.remove('SetNextAVTransportURI');
        h.clearRecords();
        respond(h, state: 'PLAYING', rel: 1, trackUri: proxyUrlFor('102'));
        h.poll(async);
        expect(h.described, isNot(contains('started(102)')));

        h.clearRecords();
        registerNext(async, h, '103');
        expect(h.api.calls, ['getPlaybackInfo:103:LOSSLESS']);
        expect(h.soap.actions, ['SetNextAVTransportURI']);
        expect(h.soap.lastNextStreamUrl, proxyUrlFor('103'));
      });
    });

    test('[DB-60] 연달아 탐색하면 두 번째의 등록과 스피커 명령은 첫 번째가 끝난 뒤에 시작한다', () {
      // DB-60: 탐색은 play · setNext 와 같은 직렬화 대상(DB-15).
      withHarness((async, h) {
        startDash(async, h);
        h.answerStartOffset(const Duration(seconds: 10));
        h.soap.hold('SetAVTransportURI');

        final first = h.seek(async, const Duration(seconds: 20));
        final second = h.seek(async, const Duration(seconds: 40));

        expect(first.completed, isFalse);
        expect(second.completed, isFalse);
        expect(h.channel.argumentsOf('registerTrackStream').map((a) => a['startPositionMs']), [20000]);
        expect(h.soap.actions, ['Stop', 'SetAVTransportURI']);

        h.soap.release('SetAVTransportURI');
        async.flushMicrotasks();

        expect(first.completed, isTrue);
        expect(second.completed, isTrue);
        expect(h.channel.argumentsOf('registerTrackStream').map((a) => a['startPositionMs']), [20000, 40000]);
        expect(h.soap.actions, ['Stop', 'SetAVTransportURI', 'Play', 'Stop', 'SetAVTransportURI', 'Play']);
        expect(h.soap.lastStreamUrl, proxyUrlAt('101', 40000));
      });
    });

    test('[DB-60] 탐색이 진행 중이면 새 재생의 스피커 명령은 탐색이 끝난 뒤에 시작한다', () {
      // DB-60, DB-15: 탐색의 재생 명령과 새 재생의 등록·SOAP 이 섞이지 않는다.
      withHarness((async, h) {
        startDash(async, h);
        h.answerStartOffset(const Duration(seconds: 10));
        h.soap.hold('SetAVTransportURI');

        h.seek(async, const Duration(seconds: 20));
        final played = h.play(async, testTrack('102'));

        expect(played.completed, isFalse);
        expect(h.channel.argumentsOf('registerTrackStream').map((a) => a['trackId']), ['101']);
        expect(h.soap.actions, ['Stop', 'SetAVTransportURI']);

        h.soap.release('SetAVTransportURI');
        async.flushMicrotasks();

        expect(played.completed, isTrue);
        expect(h.channel.argumentsOf('registerTrackStream').map((a) => a['trackId']), ['101', '102']);
        expect(h.soap.actions, ['Stop', 'SetAVTransportURI', 'Play', 'Stop', 'SetAVTransportURI', 'Play']);
        expect(h.soap.lastStreamUrl, proxyUrlFor('102'));
      });
    });

    test('[DB-60] 탐색이 진행 중이면 다음 곡 등록은 탐색이 끝난 뒤에 실행된다', () {
      // DB-60, DB-42: 탐색의 재생 명령 사이에 SetNextAVTransportURI 가 끼어들지 않는다.
      withHarness((async, h) {
        startDash(async, h);
        h.answerStartOffset(const Duration(seconds: 10));
        h.soap.hold('SetAVTransportURI');

        h.seek(async, const Duration(seconds: 20));
        registerNext(async, h, '102');

        expect(h.channel.argumentsOf('registerTrackStream').map((a) => a['trackId']), ['101']);
        expect(h.soap.actions, ['Stop', 'SetAVTransportURI']);

        h.soap.release('SetAVTransportURI');
        async.flushMicrotasks();

        expect(h.soap.actions, ['Stop', 'SetAVTransportURI', 'Play', 'SetNextAVTransportURI']);
        expect(h.soap.lastNextStreamUrl, proxyUrlFor('102'));
      });
    });

    test('[DB-61] 재생한 곡이 없을 때의 탐색은 Seek만 보낸다', () {
      // DB-61: play 전.
      withHarness((async, h) {
        h.api.defaultPlaybackInfo = dashStream();

        final result = h.seek(async, const Duration(seconds: 42, milliseconds: 900));

        expect(result.error, isNull);
        expect(h.soap.actions, ['Seek']);
        expect(h.soap.lastRelTime, '00:00:42');
        expect(h.channel.callsOf('registerTrackStream'), isEmpty);
      });
    });

    test('[DB-61] DASH 곡을 정지한 뒤의 탐색은 다시 등록하지 않고 Seek만 보낸다', () {
      // DB-61: stop() 뒤에는 재생 중인 곡이 없다.
      withHarness((async, h) {
        startDash(async, h);
        h.backend.stop();
        async.flushMicrotasks();
        h.answerStartOffset(const Duration(seconds: 40));
        h.clearRecords();

        final result = h.seek(async, const Duration(seconds: 42, milliseconds: 900));

        expect(result.error, isNull);
        expect(h.soap.actions, ['Seek']);
        expect(h.soap.lastRelTime, '00:00:42');
        expect(h.channel.callsOf('registerTrackStream'), isEmpty);
        expect(h.events, isEmpty);
      });
    });
  });

  group('탐색 중의 폴링 (dash-seek)', () {
    test('[DB-62] 탐색의 프록시 등록을 기다리는 동안에는 폴링 차례를 건너뛰고, 끝나면 다음 차례부터 이어진다', () {
      // DB-62: 탐색 중에는 SOAP 조회도 이벤트도 없다. DB-62b: 성공 뒤에는 새 흐름(오프셋 60초) 기준으로 이어진다.
      withHarness((async, h) {
        startDash(async, h, durationSeconds: 180);
        respond(h, state: 'PLAYING', rel: 5);
        h.poll(async);
        h.answerStartOffset(const Duration(seconds: 60));
        h.clearRecords();
        h.channel.hold('registerTrackStream');

        final result = h.seek(async, const Duration(seconds: 61));
        h.poll(async, 2);

        expect(result.completed, isFalse);
        expect(h.soap.countOf('GetTransportInfo'), 0);
        expect(h.soap.countOf('GetPositionInfo'), 0);
        expect(h.events, isEmpty);

        h.channel.release('registerTrackStream');
        async.flushMicrotasks();
        expect(result.completed, isTrue);
        expect(h.described, ['position(60/180)', 'state(playing,buffering)']);

        h.clearRecords();
        respond(h, state: 'PLAYING', rel: 0);
        h.poll(async);
        expect(h.soap.countOf('GetTransportInfo'), 1);
        expect(h.soap.countOf('GetPositionInfo'), 1);
        expect(h.described, ['position(60/180)', 'state(playing)']);
      });
    });

    test('[DB-62] 탐색의 스피커 명령 도중 스피커가 STOPPED라고 답할 상태여도 정지를 알리지 않는다', () {
      // DB-62: 재생 명령의 Stop 직후를 흉내 낸다. 폴링을 건너뛰므로 state(stopped) 가 나오지 않는다.
      withHarness((async, h) {
        startDash(async, h, durationSeconds: 180);
        respond(h, state: 'PLAYING', rel: 5);
        h.poll(async);
        h.answerStartOffset(const Duration(seconds: 60));
        h.clearRecords();
        h.soap
          ..transportState = 'STOPPED'
          ..positionInfo = positionInfo(rel: 0);
        h.soap.hold('SetAVTransportURI');

        final result = h.seek(async, const Duration(seconds: 61));
        h.poll(async, 2);

        expect(h.soap.actions, ['Stop', 'SetAVTransportURI']);
        expect(h.events, isEmpty);

        h.soap.release('SetAVTransportURI');
        async.flushMicrotasks();
        expect(result.error, isNull);
        expect(result.completed, isTrue);
        expect(h.soap.actions, ['Stop', 'SetAVTransportURI', 'Play']);
        expect(h.described, ['position(60/180)', 'state(playing,buffering)']);
      });
    });

    test('[DB-62] 곡 끝 근처에서 탐색하는 도중 스피커가 STOPPED라고 답할 상태여도 곡 종료를 알리지 않는다', () {
      // DB-62: 마지막 위치 178초(길이 − 3초 이상)에서 STOPPED 를 보면 곡 종료(DB-23)가 되므로, 탐색 중에는 보지 않는다.
      withHarness((async, h) {
        startDash(async, h, durationSeconds: 180);
        respond(h, state: 'PLAYING', rel: 178);
        h.poll(async);
        h.answerStartOffset(const Duration(seconds: 30));
        h.clearRecords();
        h.soap
          ..transportState = 'STOPPED'
          ..positionInfo = positionInfo(rel: 0);
        h.soap.hold('Play');

        final result = h.seek(async, const Duration(seconds: 31));
        h.poll(async, 2);

        expect(h.soap.actions, ['Stop', 'SetAVTransportURI', 'Play']);
        expect(h.events, isEmpty);

        h.soap.release('Play');
        async.flushMicrotasks();
        expect(result.completed, isTrue);
        expect(h.described, ['position(30/180)', 'state(playing,buffering)']);

        // DB-62b: 끝난 뒤에는 새 흐름(오프셋 30초, 상대) 기준으로 이어진다.
        h.clearRecords();
        respond(h, state: 'PLAYING', rel: 1);
        h.poll(async);
        expect(h.described, ['position(31/180)', 'state(playing)']);
      });
    });

    test('[DB-62b] 탐색의 프록시 등록이 실패해도 그 뒤 폴링은 탐색 전 상태 기준으로 이어진다', () {
      // DB-62: 등록을 기다리는 동안 건너뜀. DB-62b, DB-53: 실패 뒤에는 오프셋 28초 · PLAYING 을 본 상태 그대로.
      withHarness((async, h) {
        startDashAt(async, h, offsetSeconds: 28, durationSeconds: 180);
        respond(h, state: 'PLAYING', rel: 0);
        h.poll(async);
        h.clearRecords();
        h.channel.failing.add('registerTrackStream');
        h.channel.hold('registerTrackStream');

        final result = h.seek(async, const Duration(seconds: 90));
        h.poll(async, 2);

        expect(h.soap.calls, isEmpty);
        expect(h.events, isEmpty);

        h.channel.release('registerTrackStream');
        async.flushMicrotasks();
        expect(result.errorCode, 'PROXY_FAILED');
        expect(h.events, isEmpty);

        respond(h, state: 'PLAYING', rel: 0);
        respond(h, state: 'STOPPED', rel: 0);
        h.poll(async, 2);
        expect(h.soap.countOf('GetTransportInfo'), 2);
        // 탐색 전에 PLAYING 을 봤으므로 STOPPED 는 스피커 쪽 정지다(28초 < 180 − 3초).
        expect(h.described, ['position(28/180)', 'state(playing)', 'position(28/180)', 'state(stopped)']);
      });
    });

    test('[DB-62b] 탐색의 재생 명령이 거부되어도 그 뒤 폴링은 탐색 전 상태 기준으로 이어진다', () {
      // DB-62: Play 응답을 기다리는 동안 건너뜀. DB-62b, DB-53b: 실패 뒤에는 오프셋 28초 그대로(응답값 88초를 쓰지 않음).
      withHarness((async, h) {
        startDashAt(async, h, offsetSeconds: 28, durationSeconds: 180);
        respond(h, state: 'PLAYING', rel: 0);
        h.poll(async);
        h.answerStartOffset(const Duration(seconds: 88));
        h.clearRecords();
        h.soap.commandResults['Play'] = false;
        h.soap.hold('Play');

        final result = h.seek(async, const Duration(seconds: 90));
        h.poll(async, 2);

        expect(h.soap.actions, ['Stop', 'SetAVTransportURI', 'Play']);
        expect(h.events, isEmpty);

        h.soap.release('Play');
        async.flushMicrotasks();
        expect(result.errorCode, 'DLNA_PLAY_FAILED');
        expect(h.events, isEmpty);

        h.clearRecords();
        respond(h, state: 'PLAYING', rel: 0);
        h.poll(async);
        expect(h.soap.countOf('GetTransportInfo'), 1);
        expect(h.described, ['position(28/180)', 'state(playing)']);
      });
    });

    test('[DB-62c] 탐색 전에 보낸 조회의 STOPPED 응답이 탐색 도중 도착하면 버리고, 탐색 뒤 폴링은 새 흐름으로 이어진다', () {
      // DB-62c: 마지막 위치 178초(길이 − 3초 이상)에서 STOPPED 를 받으면 곡 종료(DB-23)지만, 탐색 중에 도착한 응답은 버린다.
      withHarness((async, h) {
        startDash(async, h, durationSeconds: 180);
        respond(h, state: 'PLAYING', rel: 178);
        h.poll(async);
        h.clearRecords();
        // 폴링 차례: 조회가 나가고 응답(STOPPED)은 붙잡혀 있다.
        respond(h, state: 'STOPPED', rel: 0);
        h.soap.hold('GetTransportInfo');
        h.poll(async);
        expect(h.soap.countOf('GetTransportInfo'), 1);
        // 탐색 시작: 등록 응답을 붙잡아 진행 중으로 둔다.
        h.answerStartOffset(const Duration(seconds: 30));
        h.channel.hold('registerTrackStream');
        final result = h.seek(async, const Duration(seconds: 31));
        expect(result.completed, isFalse);

        h.soap.release('GetTransportInfo');
        async.flushMicrotasks();

        expect(h.events, isEmpty);

        h.channel.release('registerTrackStream');
        async.flushMicrotasks();
        expect(result.error, isNull);
        expect(result.completed, isTrue);
        expect(h.described, ['position(30/180)', 'state(playing,buffering)']);

        // 폴링은 멈추지 않았고 새 흐름(오프셋 30초, 상대) 기준이다.
        h.clearRecords();
        respond(h, state: 'PLAYING', rel: 1);
        h.poll(async);
        expect(h.soap.countOf('GetTransportInfo'), 1);
        expect(h.described, ['position(31/180)', 'state(playing)']);
      });
    });

    test('[DB-62c] 탐색 전에 보낸 조회의 STOPPED 응답이 도착한 뒤 탐색이 실패해도 폴링은 탐색 전 상태로 이어진다', () {
      // DB-62c, DB-62b, DB-53: 버린 응답은 상태를 바꾸지 않는다(폴링 중지 없음, PLAYING 을 본 상태 · 마지막 위치 178초 유지).
      withHarness((async, h) {
        startDash(async, h, durationSeconds: 180);
        respond(h, state: 'PLAYING', rel: 178);
        h.poll(async);
        h.clearRecords();
        respond(h, state: 'STOPPED', rel: 0);
        h.soap.hold('GetTransportInfo');
        h.poll(async);
        expect(h.soap.countOf('GetTransportInfo'), 1);
        h.channel.failing.add('registerTrackStream');
        h.channel.hold('registerTrackStream');
        final result = h.seek(async, const Duration(seconds: 31));

        h.soap.release('GetTransportInfo');
        async.flushMicrotasks();

        expect(h.events, isEmpty);

        h.channel.release('registerTrackStream');
        async.flushMicrotasks();
        expect(result.errorCode, 'PROXY_FAILED');
        expect(h.events, isEmpty);

        // 폴링이 이어진다. 탐색 전 상태 그대로이므로 이후의 STOPPED 는 곡 종료다(179초 ≥ 180 − 3초).
        h.clearRecords();
        respond(h, state: 'PLAYING', rel: 179);
        respond(h, state: 'STOPPED', rel: 0);
        h.poll(async, 2);
        expect(h.soap.countOf('GetTransportInfo'), 2);
        expect(h.described, ['position(179/180)', 'state(playing)', 'position(0/180)', 'ended(101)']);
      });
    });
  });

  group('위치 보정 (dash-seek)', () {
    test('[DB-54] 첫 RelTime으로 위치 기준을 정한다: 오프셋 10초 이상이고 RelTime이 오프셋 − 2초 이상이면 절대, 아니면 상대', () {
      // DB-54: 경계는 O = 10, RelTime = O − 2. 기대 위치는 절대면 RelTime, 상대면 O + RelTime(DB-55, DB-55b).
      const cases = [
        (offset: 10, rel: 8, position: 8, why: 'O = 10, RelTime = O − 2 → 절대'),
        (offset: 10, rel: 7, position: 17, why: 'O = 10, RelTime = O − 3 → 상대'),
        (offset: 10, rel: 10, position: 10, why: 'O = 10, RelTime = O → 절대'),
        (offset: 9, rel: 7, position: 16, why: 'O = 9, RelTime = O − 2 → 상대 (O < 10)'),
        (offset: 9, rel: 9, position: 18, why: 'O = 9, RelTime = O → 상대 (O < 10)'),
        (offset: 60, rel: 58, position: 58, why: 'O = 60, RelTime = O − 2 → 절대'),
        (offset: 60, rel: 57, position: 117, why: 'O = 60, RelTime = O − 3 → 상대'),
      ];
      for (final c in cases) {
        withHarness((async, h) {
          startDashAt(async, h, offsetSeconds: c.offset, durationSeconds: 180);
          respond(h, state: 'PLAYING', rel: c.rel);

          h.poll(async);

          expect(h.described, ['position(${c.position}/180)', 'state(playing)'], reason: c.why);
        });
      }
    });

    test('[DB-54] 상대로 정한 기준은 나중 RelTime이 오프셋을 넘어도 바꾸지 않는다', () {
      // DB-54: 첫 값 3(< 60 − 2) → 상대. 이후 70(≥ 58)이 와도 상대 → 130.
      withHarness((async, h) {
        startDashAt(async, h, offsetSeconds: 60, durationSeconds: 180);
        respond(h, state: 'PLAYING', rel: 3);
        respond(h, state: 'PLAYING', rel: 70);

        h.poll(async, 2);

        expect(h.described, ['position(63/180)', 'state(playing)', 'position(130/180)', 'state(playing)']);
      });
    });

    test('[DB-54] 절대로 정한 기준은 나중 RelTime이 작아져도 바꾸지 않는다', () {
      // DB-54: 첫 값 60(≥ 58) → 절대. 이후 1이 와도 절대 → 1.
      withHarness((async, h) {
        startDashAt(async, h, offsetSeconds: 60, durationSeconds: 180);
        respond(h, state: 'PLAYING', rel: 60);
        respond(h, state: 'PLAYING', rel: 1);

        h.poll(async, 2);

        expect(h.described, ['position(60/180)', 'state(playing)', 'position(1/180)', 'state(playing)']);
      });
    });

    test('[DB-55] 위치 기준이 상대면 시작 오프셋(초 단위로 버림)에 RelTime을 더해 알린다', () {
      // DB-55: 오프셋 28.5초 → O = 28. RelTime 5 → 33초.
      withHarness((async, h) {
        h.api.defaultPlaybackInfo = dashStream();
        h.answerStartOffset(const Duration(milliseconds: 28500));
        h.play(async, testTrack('101', durationSeconds: 180), startPosition: const Duration(seconds: 30));
        h.clearRecords();
        respond(h, state: 'PLAYING', rel: 5);

        h.poll(async);

        expect((h.events.first as BackendPositionChanged).position, const Duration(seconds: 33));
        expect(h.described, ['position(33/180)', 'state(playing)']);
      });
    });

    test('[DB-55b] 위치 기준이 절대면 RelTime을 그대로 알린다', () {
      // DB-55b: O = 60, 첫 값 59 → 절대. 59, 61 그대로.
      withHarness((async, h) {
        startDashAt(async, h, offsetSeconds: 60, durationSeconds: 180);
        respond(h, state: 'PLAYING', rel: 59);
        respond(h, state: 'PLAYING', rel: 61);

        h.poll(async, 2);

        expect(h.described, ['position(59/180)', 'state(playing)', 'position(61/180)', 'state(playing)']);
      });
    });

    test('[DB-55c] 위치 기준이 정해지기 전(RelTime 0)에는 시작 오프셋을 알리고, RelTime 0으로는 기준을 정하지 않는다', () {
      // DB-55c, DB-54: 0, 0 → 60, 60. 그 뒤 첫 양수 58(= O − 2)로 절대 판정 → 58(0 으로 상대가 정해졌다면 118).
      withHarness((async, h) {
        startDashAt(async, h, offsetSeconds: 60, durationSeconds: 180);
        respond(h, state: 'PLAYING', rel: 0);
        respond(h, state: 'PLAYING', rel: 0);
        respond(h, state: 'PLAYING', rel: 58);

        h.poll(async, 3);

        expect(h.described, [
          'position(60/180)',
          'state(playing)',
          'position(60/180)',
          'state(playing)',
          'position(58/180)',
          'state(playing)',
        ]);
      });
    });

    test('[DB-56] 시작 오프셋이 있는 흐름의 길이는 렌더러 값이 아니라 곡의 길이다', () {
      // DB-56: 렌더러 TrackDuration 120(남은 흐름의 길이)을 쓰지 않고 곡 길이 180.
      withHarness((async, h) {
        startDashAt(async, h, offsetSeconds: 60, durationSeconds: 180);
        respond(h, state: 'PLAYING', rel: 5, duration: 120);

        h.poll(async);

        expect(h.described, ['position(65/180)', 'state(playing)']);
      });
    });

    test('[DB-56] 시작 오프셋이 있는 흐름에서 곡의 길이를 모르면 길이 없이 알린다', () {
      // DB-56: 곡 정보에 길이가 없으면 null(렌더러 값 120 을 쓰지 않음).
      withHarness((async, h) {
        startDashAt(async, h, offsetSeconds: 60, durationSeconds: 0);
        respond(h, state: 'PLAYING', rel: 5, duration: 120);

        h.poll(async);

        expect(h.described, ['position(65/-)', 'state(playing)']);
        expect((h.events.first as BackendPositionChanged).duration, isNull);
      });
    });

    test('[DB-56b] 곡 끝은 보정한 위치로 판정한다: 길이 − 3초 이상이면 곡 종료, 그보다 앞이면 스피커 쪽 정지', () {
      // DB-56b, DB-23, DB-25: O = 170(상대), 길이 180. RelTime 7 → 177(종료), 6 → 176(정지).
      withHarness((async, h) {
        startDashAt(async, h, offsetSeconds: 170, durationSeconds: 180);
        respond(h, state: 'PLAYING', rel: 7);
        respond(h, state: 'STOPPED');

        h.poll(async, 2);

        expect(h.described, ['position(177/180)', 'state(playing)', 'ended(101)']);
      });
      withHarness((async, h) {
        startDashAt(async, h, offsetSeconds: 170, durationSeconds: 180);
        respond(h, state: 'PLAYING', rel: 6);
        respond(h, state: 'STOPPED');

        h.poll(async, 2);

        expect(h.described, ['position(176/180)', 'state(playing)', 'state(stopped)']);
      });
    });

    test('[DB-56b] 위치 기준이 절대면 오프셋을 더하지 않은 위치로 곡 끝을 판정한다', () {
      // DB-56b: O = 100, 첫 값 100 → 절대, 위치 100(< 177) → 스피커 쪽 정지(오프셋을 더한 200 으로 보면 곡 종료).
      withHarness((async, h) {
        startDashAt(async, h, offsetSeconds: 100, durationSeconds: 180);
        respond(h, state: 'PLAYING', rel: 100);
        respond(h, state: 'STOPPED');

        h.poll(async, 2);

        expect(h.described, ['position(100/180)', 'state(playing)', 'state(stopped)']);
      });
    });

    test('[DB-56b] 멈춘 시점에 RelTime이 0이면 직전의 보정 위치로 판정한다', () {
      // DB-56b, DB-26: RelTime 8 → 178 을 기억. 이어진 RelTime 0(알리는 위치 170)은 기억하지 않는다 → 곡 종료.
      withHarness((async, h) {
        startDashAt(async, h, offsetSeconds: 170, durationSeconds: 180);
        respond(h, state: 'PLAYING', rel: 8);
        respond(h, state: 'STOPPED', rel: 0);

        h.poll(async, 2);

        expect(h.described, ['position(178/180)', 'state(playing)', 'position(170/180)', 'ended(101)']);
      });
    });

    test('[DB-58] 갭리스로 넘어가면 시작 오프셋이 0이 되어 새 곡의 위치와 길이를 그대로 알린다', () {
      // DB-58, DB-17: 앞 곡의 오프셋 60 을 더하지 않고, 렌더러 길이 200 을 쓴다.
      withHarness((async, h) {
        startDashAt(async, h, offsetSeconds: 60, durationSeconds: 180);
        registerNext(async, h, '102', durationSeconds: 240);
        h.clearRecords();
        respond(h, state: 'PLAYING', rel: 1, trackUri: proxyUrlFor('102'));
        respond(h, state: 'PLAYING', rel: 5, duration: 200, trackUri: proxyUrlFor('102'));

        h.poll(async, 2);

        expect(h.described, ['started(102)', 'position(5/200)', 'state(playing)']);
      });
    });

    test('[DB-58] 새로 재생하면 시작 오프셋이 0이 된다', () {
      // DB-58, DB-17: 앞 곡의 오프셋 60 이 남지 않는다.
      withHarness((async, h) {
        startDashAt(async, h, offsetSeconds: 60);
        startPlaying(async, h, id: '102', durationSeconds: 180);
        respond(h, state: 'PLAYING', rel: 5, duration: 200);

        h.poll(async);

        expect(h.described, ['position(5/200)', 'state(playing)']);
      });
    });

    test('[DB-58] 새로 재생하면 위치 기준을 다시 정한다', () {
      // DB-58, DB-54: 앞 곡에서 절대로 정했어도 새 곡의 첫 RelTime(5 < 60 − 2)으로 다시 판정 → 상대 65.
      withHarness((async, h) {
        startDashAt(async, h, offsetSeconds: 60);
        respond(h, state: 'PLAYING', rel: 60);
        h.poll(async);
        expect(h.described, ['position(60/180)', 'state(playing)']);

        startDashAt(async, h, id: '102', offsetSeconds: 60);
        respond(h, state: 'PLAYING', rel: 5);
        h.poll(async);

        expect(h.described, ['position(65/180)', 'state(playing)']);
      });
    });
  });

  group('주소 재발급', () {
    Object? refresh(FakeAsync async, DlnaBackendHarness h, String trackId) {
      Object? reply = 'no reply';
      h.channel.invokeFromNative('refreshTrackStream', {'trackId': trackId}).then((value) => reply = value);
      async.flushMicrotasks();
      return reply;
    }

    test('[DB-48] 네이티브가 주소 재발급을 요청하면 지금 음질로 다시 조회한 스트림 정보를 돌려준다', () {
      withHarness((async, h) {
        h.backend.setAudioQuality('HI_RES_LOSSLESS');
        async.flushMicrotasks();

        final reply = refresh(async, h, '101');

        expect(reply, {
          'directUrl': 'https://cdn.example.test/tracks/direct.flac',
          'manifestXml': '',
          'mimeType': 'audio/flac',
        });
        expect(h.api.calls, ['getPlaybackInfo:101:HI_RES_LOSSLESS']);
      });
    });

    test('[DB-49] 사용자 토큰이 없거나 스트림 정보를 받지 못하면 null을 돌려준다', () {
      withHarness((async, h) {
        h.auth.validUserToken = null;
        expect(refresh(async, h, '101'), isNull);
        expect(h.api.calls, isEmpty);
      });
      withHarness((async, h) {
        h.api.defaultPlaybackInfo = null;
        expect(refresh(async, h, '101'), isNull);
      });
    });
  });

  group('속성', () {
    /// 폴링 응답 순서를 실제 백엔드와 모델 양쪽에 하나씩 넣고, 매번 이벤트와 잠금 상태를 비교한다.
    void checkAgainstModel(List<PollResponse> responses, {required int trackSeconds}) {
      withHarness((async, h) {
        startPlaying(async, h, durationSeconds: trackSeconds);
        final model = PollModel(trackId: '101', trackSeconds: trackSeconds);
        final expected = <String>[];
        var expectedPolls = 0;

        // 응답이 하나도 없을 때: 이벤트가 없고 폴링 중이다.
        expect(h.described, isEmpty);
        expect(lastStreamingLock(h) ?? true, isTrue);

        for (final response in responses) {
          if (model.polling) expectedPolls++;
          h.soap.transportStates.add(response.state);
          h.soap.positionInfos.add(response.relSeconds == null
              ? null
              : positionInfo(rel: response.relSeconds!, duration: response.durationSeconds));
          h.poll(async);
          expected.addAll(model.step(response));

          final reason = '응답: $response / 전체: $responses';
          expect(h.described, expected, reason: reason);
          // [P-DB-2] 스트리밍 잠금은 폴링 중일 때만 켜져 있다(재생 시작 때 켠 뒤로 호출이 없으면 켜진 상태).
          expect(lastStreamingLock(h) ?? true, model.polling, reason: reason);
          expect(h.soap.countOf('GetTransportInfo'), expectedPolls, reason: reason);
        }
      });
    }

    property('[P-DB-1, P-DB-2] 어떤 폴링 응답 순서에도 이벤트와 스트리밍 잠금이 모델과 같다 (길이 180초 곡)', () {
      forAll(pollSequences(180), (responses) => checkAgainstModel(responses, trackSeconds: 180));
    });

    property('[P-DB-1, P-DB-2] 어떤 폴링 응답 순서에도 이벤트와 스트리밍 잠금이 모델과 같다 (길이를 모르는 곡)', () {
      forAll(pollSequences(0), (responses) => checkAgainstModel(responses, trackSeconds: 0));
    });

    property('[P-DB-3] 다음 곡 주소는 스킴·호스트·포트·앞뒤 공백이 달라도 알아보고, 경로나 쿼리가 다르면 알아보지 않는다', () {
      /// 다음 곡을 등록한 뒤 스피커가 [reportedUri]를 재생 중이라고 답했을 때 나온 이벤트.
      List<String> eventsFor(String reportedUri) {
        late List<String> described;
        withHarness((async, h) {
          startPlaying(async, h);
          h.backend.setNext(testTrack('102'));
          async.flushMicrotasks();
          h.clearRecords();
          respond(h, state: 'PLAYING', rel: 1, trackUri: reportedUri);
          h.poll(async);
          described = h.described;
        });
        return described;
      }

      forAll(combine2(urlRewrites(), urlMismatches()), (input) {
        final (rewrite, mismatch) = input;
        final registered = proxyUrlFor('102');

        expect(eventsFor(rewrite.apply(registered)), ['started(102)'], reason: '$rewrite');
        expect(eventsFor(mismatch.apply(registered)), isNot(contains('started(102)')), reason: '$mismatch');
      });
    });

    property('[P-DB-4] 어떤 주소의 스피커든 프록시 등록의 허용 주소는 그 스피커의 호스트다', () {
      forAll(combine2(ipv4Hosts(), ports()), (input) {
        final (host, port) = input;
        withHarness((async, h) {
          h.play(async, testTrack('101'));

          expect(h.channel.argumentsOf('registerTrackStream').single['allowedHost'], host);
        }, device: remoteSpeaker(host: host, port: port));
      });
    });

    property('[P-DB-6] 시작 오프셋이 있는 흐름의 위치는 첫 RelTime으로 정한 기준을 끝까지 따르고 줄어들지 않는다', () {
      forAll(offsetFlows(), (flow) {
        withHarness((async, h) {
          startDashAt(async, h, offsetSeconds: flow.offsetSeconds, durationSeconds: 36000);
          for (final rel in flow.relSeconds) {
            respond(h, state: 'PLAYING', rel: rel);
          }

          h.poll(async, flow.relSeconds.length);

          // 첫 값이 O − 2 이상이면 RelTime 그대로, 미만이면 O + RelTime.
          final absolute = flow.relSeconds.first >= flow.offsetSeconds - 2;
          final positions = h.events.whereType<BackendPositionChanged>().map((e) => e.position.inSeconds).toList();
          expect(
            positions,
            [for (final rel in flow.relSeconds) absolute ? rel : flow.offsetSeconds + rel],
            reason: '$flow',
          );
          for (var i = 1; i < positions.length; i++) {
            expect(positions[i], greaterThanOrEqualTo(positions[i - 1]), reason: '$flow');
          }
        });
      });
    });

    property('[P-DB-7] 어떤 시작 위치든 DASH 곡은 startPositionMs로만, 단일 파일 곡은 Seek로만 넘긴다', () {
      forAll(startRequests(), (request) {
        withHarness((async, h) {
          h.api.defaultPlaybackInfo = request.dash ? dashStream() : directStream();

          h.play(async, testTrack('101'), startPosition: request.startPosition);

          final ms = request.startPosition.inMilliseconds;
          expect(
            h.channel.argumentsOf('registerTrackStream').single['startPositionMs'],
            request.dash ? ms : 0,
            reason: '$request',
          );
          expect(h.soap.countOf('Seek'), !request.dash && ms > 0 ? 1 : 0, reason: '$request');
        });
      });
    });

    property('[P-DB-5] 스피커가 알려준 어떤 위치(초)든 같은 위치로 알린다', () {
      forAll(seconds(), (s) {
        withHarness((async, h) {
          startPlaying(async, h);
          respond(h, state: 'PLAYING', rel: s);

          h.poll(async);

          expect((h.events.first as BackendPositionChanged).position, Duration(seconds: s));
        });
      });
    });
  });
}
