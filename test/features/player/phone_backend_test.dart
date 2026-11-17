import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiri_check/kiri_check.dart' show forAll, integer, property;
import 'package:tidal_connect_lite/features/player/data/backends/phone_backend.dart';
import 'package:tidal_connect_lite/features/player/data/backends/playback_backend.dart';

import '../../helpers/event_descriptions.dart';
import '../../helpers/fake_native_channel.dart';
import '../../helpers/generators.dart';
import '../../helpers/pbt_config.dart';
import '../../helpers/playback_fixtures.dart';

// PhoneBackend 테스트. 규칙 ID(PB-xx)와 속성 ID(P-PB-x)는
// aidlc-docs/construction/dart-playback-tests/functional-design/ 의
// business-rules.md 1절, business-logic-model.md 5절을 가리킨다.

/// 재생 시작 뒤 탐색(pending seek)의 모델. business-logic-model.md 1.3의 상태 기계를 옮긴 것이다.
/// 대기 중인 시작 위치는 "없음" 또는 "있음(밀리초)" 둘 중 하나다.
class PendingSeekModel {
  int? _pendingMs;

  /// 동작 하나를 적용하고, 그 동작으로 나가야 하는 `seekTrack`의 위치(밀리초) 목록을 돌려준다.
  List<int> apply(PhoneAction action) {
    switch (action) {
      case PhonePlay(:final startSeconds):
        _pendingMs = startSeconds > 0 ? startSeconds * 1000 : null;
        return const [];
      case PhoneStateEvent(:final state):
        final pending = _pendingMs;
        if (state != 'PLAYING' || pending == null) return const [];
        _pendingMs = null;
        return [pending];
      case PhoneStop():
        _pendingMs = null;
        return const [];
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  configurePbt();

  late VoidCallback restoreLogs;
  setUpAll(() => restoreLogs = muteDebugLogs());
  tearDownAll(() => restoreLogs());

  late FakeNativeChannel channel;
  late StreamController<Map<String, dynamic>> native;
  late PhoneBackend backend;
  late List<BackendEvent> events;

  setUp(() {
    channel = FakeNativeChannel()..install();
    addTearDown(channel.uninstall);
    native = StreamController<Map<String, dynamic>>(sync: true);
    backend = PhoneBackend(nativeEvents: native.stream);
    events = [];
    backend.events.listen(events.add);
  });

  /// 네이티브 이벤트 하나를 보내고 백엔드 이벤트가 전달될 때까지 기다린다.
  Future<void> emit(Map<String, dynamic> event) async {
    native.add(event);
    await pumpEventQueue();
  }

  List<int> seekPositions() => channel.argumentsOf('seekTrack').map((a) => a['positionMs']! as int).toList();

  group('명령 → 채널 호출', () {
    test('[PB-01] 재생은 playTrack을 곡 ID와 함께 한 번 호출한다', () async {
      await backend.play(testTrack('101'), isCancelled: () => false);

      expect(channel.methods, ['playTrack']);
      expect(channel.argumentsOf('playTrack').single, {'trackId': '101'});
    });

    test('[PB-02] 재생 명령이 실패하면 PHONE_PLAY_FAILED 예외를 던진다', () async {
      channel.failing.add('playTrack');

      await expectLater(
        backend.play(testTrack('101'), isCancelled: () => false),
        throwsPlaybackException('PHONE_PLAY_FAILED'),
      );
    });

    test('[PB-03] 재생 명령이 실패해도 요청이 취소되었으면 예외를 던지지 않는다', () async {
      channel.failing.add('playTrack');

      await backend.play(testTrack('101'), isCancelled: () => true);

      expect(channel.methods, ['playTrack']);
    });

    test('[PB-04] 일시정지는 pauseTrack을 호출한다', () async {
      await backend.pause();

      expect(channel.methods, ['pauseTrack']);
    });

    test('[PB-04] 일시정지가 실패하면 PHONE_PAUSE_FAILED 예외를 던진다', () async {
      channel.failing.add('pauseTrack');

      await expectLater(backend.pause(), throwsPlaybackException('PHONE_PAUSE_FAILED'));
    });

    test('[PB-05] 재개는 resumeTrack을 호출한다', () async {
      await backend.resume();

      expect(channel.methods, ['resumeTrack']);
    });

    test('[PB-05] 재개가 실패하면 PHONE_RESUME_FAILED 예외를 던진다', () async {
      channel.failing.add('resumeTrack');

      await expectLater(backend.resume(), throwsPlaybackException('PHONE_RESUME_FAILED'));
    });

    test('[PB-06] 탐색은 seekTrack을 밀리초 위치와 함께 호출한다', () async {
      await backend.seek(const Duration(seconds: 42, milliseconds: 500));

      expect(channel.argumentsOf('seekTrack').single, {'positionMs': 42500});
    });

    test('[PB-06] 탐색이 실패해도 예외를 던지지 않는다', () async {
      channel.failing.add('seekTrack');

      await backend.seek(const Duration(seconds: 1));

      expect(channel.methods, ['seekTrack']);
    });

    test('[PB-07] 정지는 stopTrack을 호출하고, 실패해도 예외를 던지지 않는다', () async {
      await backend.stop();
      channel.failing.add('stopTrack');
      await backend.stop();

      expect(channel.methods, ['stopTrack', 'stopTrack']);
    });

    test('[PB-08] 음질 설정은 setAudioQuality를 음질 이름과 함께 호출하고, 실패해도 예외를 던지지 않는다', () async {
      await backend.setAudioQuality('HI_RES_LOSSLESS');
      channel.failing.add('setAudioQuality');
      await backend.setAudioQuality('LOW');

      expect(channel.argumentsOf('setAudioQuality'), [
        {'quality': 'HI_RES_LOSSLESS'},
        {'quality': 'LOW'},
      ]);
    });

    test('[PB-09] 다음 곡 등록은 setNextTrack을 곡 ID와 함께 호출한다', () async {
      await backend.setNext(testTrack('202'));

      expect(channel.argumentsOf('setNextTrack').single, {'trackId': '202'});
    });

    test('[PB-09] 다음 곡이 없으면 빈 곡 ID로 등록을 지우고, 실패해도 예외를 던지지 않는다', () async {
      await backend.setNext(null);
      channel.failing.add('setNextTrack');
      await backend.setNext(testTrack('202'));

      expect(channel.argumentsOf('setNextTrack').first, {'trackId': ''});
      expect(channel.methods, ['setNextTrack', 'setNextTrack']);
    });

    test('[PB-10] 폰 출력은 항상 탐색할 수 있다', () {
      expect(backend.canSeek, isTrue);
    });
  });

  group('재생 시작 뒤 탐색', () {
    test('[PB-11] 시작 위치가 있으면 재생 직후가 아니라 첫 PLAYING에서 한 번만 탐색한다', () async {
      await backend.play(testTrack('101'), startPosition: const Duration(seconds: 30), isCancelled: () => false);
      expect(seekPositions(), isEmpty);

      await emit({'type': 'state', 'state': 'PLAYING'});
      expect(seekPositions(), [30000]);

      await emit({'type': 'state', 'state': 'PLAYING'});
      expect(seekPositions(), [30000]);
    });

    test('[PB-12] 시작 위치가 0이면 PLAYING이 와도 탐색하지 않는다', () async {
      await backend.play(testTrack('101'), isCancelled: () => false);

      await emit({'type': 'state', 'state': 'PLAYING'});

      expect(seekPositions(), isEmpty);
    });

    test('[PB-13] PLAYING 전에 정지하면 시작 위치를 버린다', () async {
      await backend.play(testTrack('101'), startPosition: const Duration(seconds: 30), isCancelled: () => false);
      await backend.stop();

      await emit({'type': 'state', 'state': 'PLAYING'});

      expect(seekPositions(), isEmpty);
    });

    test('[PB-14] 새 재생 요청이 이전 요청의 시작 위치를 대체한다', () async {
      await backend.play(testTrack('101'), startPosition: const Duration(seconds: 30), isCancelled: () => false);
      await backend.play(testTrack('102'), isCancelled: () => false);

      await emit({'type': 'state', 'state': 'PLAYING'});

      expect(seekPositions(), isEmpty);
    });

    test('[PB-15] STALLED에서는 탐색하지 않고 PLAYING을 기다린다', () async {
      await backend.play(testTrack('101'), startPosition: const Duration(seconds: 30), isCancelled: () => false);

      await emit({'type': 'state', 'state': 'STALLED'});
      expect(seekPositions(), isEmpty);

      await emit({'type': 'state', 'state': 'PLAYING'});
      expect(seekPositions(), [30000]);
    });
  });

  group('이벤트 변환', () {
    test('[PB-16] PLAYING은 재생 중으로 알린다', () async {
      await emit({'type': 'state', 'state': 'PLAYING'});

      expect(describeEvents(events), ['state(playing)']);
    });

    test('[PB-17] STALLED는 재생 중이면서 버퍼링 중으로 알린다', () async {
      await emit({'type': 'state', 'state': 'STALLED'});

      expect(describeEvents(events), ['state(playing,buffering)']);
    });

    test('[PB-18] 그 밖의 상태와 상태가 없는 이벤트는 정지로 알린다', () async {
      await emit({'type': 'state', 'state': 'NOT_PLAYING'});
      await emit({'type': 'state', 'state': 'IDLE'});
      await emit({'type': 'state'});

      expect(describeEvents(events), ['state(stopped)', 'state(stopped)', 'state(stopped)']);
    });

    test('[PB-19] position은 밀리초 위치로 알리고, 위치가 없으면 0이다', () async {
      await emit({'type': 'position', 'positionMs': 12345});
      await emit({'type': 'position'});

      final positions = events.cast<BackendPositionChanged>().map((e) => e.position.inMilliseconds);
      expect(positions, [12345, 0]);
    });

    test('[PB-20] 위치 알림의 길이는 재생을 요청한 곡의 길이이고, transition이 오면 그 길이로 바뀐다', () async {
      await emit({'type': 'position', 'positionMs': 1000});
      await backend.play(testTrack('101', durationSeconds: 180), isCancelled: () => false);
      await emit({'type': 'position', 'positionMs': 2000});
      await emit({'type': 'transition', 'trackId': '101', 'durationMs': 200000});
      await emit({'type': 'position', 'positionMs': 3000});

      final durations = events.whereType<BackendPositionChanged>().map((e) => e.duration?.inSeconds);
      expect(durations, [null, 180, 200]);
    });

    test('[PB-20] 길이가 0인 곡은 길이를 모르는 것으로 알린다', () async {
      await backend.play(testTrack('101', durationSeconds: 0), isCancelled: () => false);
      await emit({'type': 'position', 'positionMs': 2000});

      expect((events.single as BackendPositionChanged).duration, isNull);
    });

    test('[PB-21] transition은 곡 시작으로 알리고 길이와 음질을 싣는다', () async {
      await emit({
        'type': 'transition',
        'trackId': '101',
        'durationMs': 201500,
        'preview': true,
        'audioQuality': 'HI_RES_LOSSLESS',
        'bitDepth': 24,
        'sampleRate': 96000,
        'codec': 'flac',
      });

      final started = events.single as BackendTrackStarted;
      expect(started.trackId, '101');
      expect(started.duration, const Duration(milliseconds: 201500));
      expect(started.quality!.audioQuality, 'HI_RES_LOSSLESS');
      expect(started.quality!.bitDepth, 24);
      expect(started.quality!.sampleRate, 96000);
      expect(started.quality!.codec, 'flac');
      expect(started.quality!.preview, isTrue);
    });

    test('[PB-21] transition에 필드가 없으면 길이는 모름, 음질 이름은 빈 문자열, 미리듣기는 아님이다', () async {
      await emit({'type': 'transition', 'trackId': '101', 'durationMs': 0});
      await emit({'type': 'transition'});

      final first = events[0] as BackendTrackStarted;
      expect(first.duration, isNull);
      expect(first.quality!.audioQuality, '');
      expect(first.quality!.bitDepth, isNull);
      expect(first.quality!.preview, isFalse);
      expect((events[1] as BackendTrackStarted).trackId, '');
    });

    test('[PB-22] ended는 그 곡의 종료로 알린다', () async {
      await emit({'type': 'ended', 'trackId': '101'});

      expect(describeEvents(events), ['ended(101)']);
    });

    test('[PB-22] ended에 곡 ID가 없으면 현재 곡으로, 현재 곡도 없으면 빈 ID로 알린다', () async {
      await emit({'type': 'ended'});
      await backend.play(testTrack('101'), isCancelled: () => false);
      await emit({'type': 'ended'});
      await emit({'type': 'transition', 'trackId': '102'});
      await emit({'type': 'ended'});

      expect(describeEvents(events), ['ended()', 'ended(101)', 'started(102)', 'ended(102)']);
    });

    test('[PB-23] error는 코드와 메시지를 그대로 알린다', () async {
      await emit({'type': 'error', 'code': 'PRIVILEGES_REVOKED', 'message': '다른 기기에서 재생 중'});

      final error = events.single as BackendError;
      expect(error.code, 'PRIVILEGES_REVOKED');
      expect(error.message, '다른 기기에서 재생 중');
    });

    test('[PB-23] error에 코드와 메시지가 없으면 UNKNOWN과 기본 문구를 쓴다', () async {
      await emit({'type': 'error'});

      final error = events.single as BackendError;
      expect(error.code, 'UNKNOWN');
      expect(error.message, '재생 오류');
    });

    test('[PB-24] 모르는 종류의 이벤트는 무시한다', () async {
      await emit({'type': 'phoneVolume', 'percent': 40});
      await emit({'type': 'something-else'});
      await emit(<String, dynamic>{});

      expect(events, isEmpty);
    });
  });

  group('스트림 오류와 정리', () {
    test('[PB-25] 네이티브 이벤트 스트림의 오류는 무시하고 다음 이벤트를 계속 처리한다', () async {
      native.addError(StateError('채널 끊김'));
      await pumpEventQueue();
      await emit({'type': 'state', 'state': 'PLAYING'});

      expect(describeEvents(events), ['state(playing)']);
    });

    test('[PB-26] dispose는 네이티브 구독을 끊고 이벤트 스트림을 닫는다', () async {
      var closed = false;
      backend.events.listen(null, onDone: () => closed = true);
      expect(native.hasListener, isTrue);

      backend.dispose();
      await pumpEventQueue();

      expect(native.hasListener, isFalse);
      expect(closed, isTrue);
    });
  });

  group('속성', () {
    /// 새 백엔드에 [inputs]를 순서대로 넣고 나온 이벤트를 돌려준다. 예시마다 새 객체를 쓴다.
    List<BackendEvent> convert(List<Map<String, dynamic>> inputs) {
      final out = <BackendEvent>[];
      fakeAsync((async) {
        final source = StreamController<Map<String, dynamic>>(sync: true);
        final subject = PhoneBackend(nativeEvents: source.stream);
        subject.events.listen(out.add);
        inputs.forEach(source.add);
        async.flushMicrotasks();
        subject.dispose();
        async.flushMicrotasks();
      });
      return out;
    }

    property('[P-PB-1] 계약 범위의 어떤 이벤트에도 예외가 없고, 알려진 5종이면 이벤트 1개, 아니면 0개가 나온다', () {
      const known = {'state', 'position', 'transition', 'ended', 'error'};
      forAll(nativeEvents(), (event) {
        final out = convert([event]);

        expect(out.length, known.contains(event['type']) ? 1 : 0, reason: '$event');
      });
    });

    property('[P-PB-2] 어떤 상태 이름이든 PLAYING·STALLED만 재생 중이고 STALLED만 버퍼링이다', () {
      forAll(playerStates(), (state) {
        final out = convert([
          {'type': 'state', 'state': state}
        ]);

        final changed = out.single as BackendStateChanged;
        expect(changed.playing, state == 'PLAYING' || state == 'STALLED', reason: state);
        expect(changed.buffering, state == 'STALLED', reason: state);
      });
    });

    property('[P-PB-3] 0 이상의 어떤 positionMs든 같은 밀리초 위치로 알린다', () {
      forAll(integer(min: 0, max: 36000000), (ms) {
        final out = convert([
          {'type': 'position', 'positionMs': ms}
        ]);

        expect((out.single as BackendPositionChanged).position, Duration(milliseconds: ms));
      });
    });

    property('[P-PB-4] transition의 길이는 durationMs가 양수일 때만 있고, 있는 필드 값은 그대로 전달된다', () {
      forAll(nativeEvents(), (fields) {
        final event = {...fields, 'type': 'transition'};

        final started = convert([event]).single as BackendTrackStarted;

        final durationMs = event['durationMs'] as int?;
        expect(started.duration == null, durationMs == null || durationMs <= 0, reason: '$event');
        if (started.duration != null) expect(started.duration!.inMilliseconds, durationMs);
        expect(started.trackId, event['trackId'] ?? '');
        expect(started.quality!.audioQuality, event['audioQuality'] ?? '');
        expect(started.quality!.bitDepth, event['bitDepth']);
        expect(started.quality!.sampleRate, event['sampleRate']);
        expect(started.quality!.codec, event['codec']);
        expect(started.quality!.preview, event['preview'] == true);
      });
    });

    property('[P-PB-5] 재생·상태 이벤트·정지를 어떤 순서로 해도 시작 위치 탐색이 모델과 같은 시점·같은 값으로 일어난다', () {
      forAll(phoneActionSequences(), (actions) {
        fakeAsync((async) {
          final nativeChannel = FakeNativeChannel()..install();
          final source = StreamController<Map<String, dynamic>>(sync: true);
          final subject = PhoneBackend(nativeEvents: source.stream);
          final model = PendingSeekModel();
          final expected = <int>[];

          List<int> actual() => nativeChannel.argumentsOf('seekTrack').map((a) => a['positionMs']! as int).toList();

          // 동작이 하나도 없을 때도 탐색은 없어야 한다.
          expect(actual(), isEmpty);
          for (final action in actions) {
            switch (action) {
              case PhonePlay(:final startSeconds):
                subject.play(
                  testTrack('101'),
                  startPosition: Duration(seconds: startSeconds),
                  isCancelled: () => false,
                );
              case PhoneStateEvent(:final state):
                source.add({'type': 'state', 'state': state});
              case PhoneStop():
                subject.stop();
            }
            async.flushMicrotasks();
            expected.addAll(model.apply(action));

            // 동작 하나마다 실제 호출과 모델을 비교한다.
            expect(actual(), expected, reason: '동작: $action / 전체: $actions');
          }

          subject.dispose();
          nativeChannel.uninstall();
          async.flushMicrotasks();
        });
      });
    });
  });
}
