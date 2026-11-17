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

    test('[DB-12] DASH 스트림은 시작 위치가 있어도 탐색하지 않는다', () {
      withHarness((async, h) {
        h.api.defaultPlaybackInfo = dashStream();

        h.play(async, testTrack('101'), startPosition: const Duration(seconds: 30));

        expect(h.soap.actions, ['Stop', 'SetAVTransportURI', 'Play']);
      });
    });

    test('[DB-13] 탐색 가능 여부는 처음에는 가능, DASH 곡을 보내면 불가, 단일 파일 곡을 보내면 다시 가능이다', () {
      withHarness((async, h) {
        expect(h.backend.canSeek, isTrue);

        h.api.playbackInfos['101'] = dashStream();
        h.play(async, testTrack('101'));
        expect(h.backend.canSeek, isFalse);

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
    void setNext(FakeAsync async, DlnaBackendHarness h, String? id, {int durationSeconds = 240}) {
      h.backend.setNext(id == null ? null : testTrack(id, durationSeconds: durationSeconds));
      async.flushMicrotasks();
    }

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
        expect(h.backend.canSeek, isFalse);

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

    test('[DB-45] 탐색은 초 단위 위치로 Seek를 보내고, 거부되어도 예외를 던지지 않는다', () {
      withHarness((async, h) {
        h.soap.commandResults['Seek'] = false;

        final result = capture(h.backend.seek(const Duration(seconds: 42, milliseconds: 900)));
        async.flushMicrotasks();

        expect(result.error, isNull);
        expect(h.soap.actions, ['Seek']);
        expect(h.soap.lastRelTime, '00:00:42');
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
