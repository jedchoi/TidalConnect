import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiri_check/kiri_check.dart' show forAll, property;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tidal_connect_lite/features/dlna/data/dlna_manager.dart';
import 'package:tidal_connect_lite/features/dlna/domain/models/dlna_device.dart';
import 'package:tidal_connect_lite/features/player/data/backends/playback_backend.dart';
import 'package:tidal_connect_lite/features/player/data/player_manager.dart';
import 'package:tidal_connect_lite/features/player/data/wave_audio_handler.dart';

import '../../helpers/app_overrides.dart';
import '../../helpers/fake_backend.dart';
import '../../helpers/fake_native_channel.dart';
import '../../helpers/fake_soap_client.dart';
import '../../helpers/fakes.dart';
import '../../helpers/generators.dart';
import '../../helpers/pbt_config.dart';
import '../../helpers/playback_fixtures.dart';

// WaveAudioHandler 테스트. 규칙 ID(WA-xx)와 속성 ID(P-WA-x)는
// aidlc-docs/construction/dart-playback-tests/functional-design/ 의
// business-rules.md 4절, business-logic-model.md 5절을 가리킨다.
//
// PlayerManager는 실제 객체를 쓰고 그 출력 기기만 FakeBackend로 바꾼다.
// 명령 전달은 PlayerManager의 상태나 FakeBackend의 기록으로 확인한다.

/// 테스트 하나가 쓰는 객체 묶음.
class _Subject {
  _Subject() {
    manager = DlnaManager.forTesting(ssdpService: FakeSsdpDiscoveryService(), soapClient: soap);
    player = PlayerManager.forTesting()
      ..configure(
        authRepository: FakeAuthRepository(),
        dlnaManager: manager,
        apiClient: FakeApiClient(),
        phone: phone,
        dlna: dlna,
      );
    handler = WaveAudioHandler(player, dlnaManager: manager);
  }

  final phone = FakeBackend();
  final dlna = FakeBackend();
  final soap = FakeSoapClient();
  late final DlnaManager manager;
  late final PlayerManager player;
  late final WaveAudioHandler handler;

  PlaybackState get state => handler.playbackState.value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  configurePbt();

  late VoidCallback restoreLogs;
  setUpAll(() => restoreLogs = muteDebugLogs());
  tearDownAll(() => restoreLogs());

  late FakeNativeChannel channel;
  late _Subject s;
  final playlist = [testTrack('1'), testTrack('2'), testTrack('3')];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    channel = FakeNativeChannel()..install();
    addTearDown(channel.uninstall);
    s = _Subject();
  });

  /// 첫 곡을 재생 중인 상태로 만든다.
  Future<void> startPlaying({int index = 0}) async {
    await s.player.playTrack(playlist[index], queue: playlist, index: index);
    s.phone.controller.add(const BackendStateChanged(playing: true));
  }

  group('명령 전달', () {
    test('[WA-01] 재생 버튼은 재개를 요청한다', () async {
      await startPlaying();
      s.phone.controller.add(const BackendStateChanged(playing: false));

      await s.handler.play();

      expect(s.phone.commands, ['resume']);
      expect(s.player.isPlaying, isTrue);
    });

    test('[WA-02] 일시정지 버튼은 일시정지를 요청한다', () async {
      await startPlaying();

      await s.handler.pause();

      expect(s.phone.commands, ['pause']);
      expect(s.player.isPlaying, isFalse);
    });

    test('[WA-03] 정지는 재생을 멈춘다', () async {
      await startPlaying();

      await s.handler.stop();

      expect(s.phone.commands, ['stop']);
      expect(s.player.isPlaying, isFalse);
      expect(s.state.playing, isFalse);
    });

    test('[WA-04] 탐색은 초 단위 위치로 요청한다', () async {
      await startPlaying();

      await s.handler.seek(const Duration(seconds: 42, milliseconds: 700));

      expect(s.phone.commands, ['seek:42']);
      expect(s.player.progressSeconds, 42);
    });

    test('[WA-05] 다음 곡·이전 곡 버튼은 대기열의 다음·이전 곡을 재생한다', () async {
      await startPlaying();

      await s.handler.skipToNext();
      await pumpEventQueue();
      expect(s.phone.played, ['1', '2']);

      await s.handler.skipToPrevious();
      await pumpEventQueue();
      expect(s.phone.played, ['1', '2', '1']);
    });

    test('[WA-06] 대기열의 곡을 고르면 그 곡을 재생한다', () async {
      await startPlaying();

      await s.handler.skipToQueueItem(2);
      await pumpEventQueue();

      expect(s.phone.played, ['1', '3']);
      expect(s.player.currentTrack!.id, '3');
    });

    test('[WA-07] 앱을 최근 목록에서 밀어내면 재생을 멈춘다', () async {
      await startPlaying();

      await s.handler.onTaskRemoved();

      expect(s.phone.commands, ['stop']);
      expect(s.player.isPlaying, isFalse);
    });

    test('[WA-08] 원격 볼륨 올림·내림은 볼륨을 한 단계씩 바꾸고, 변화 없음은 아무것도 하지 않는다', () async {
      final before = s.player.volumeNotifier.value;

      await s.handler.androidAdjustRemoteVolume(AndroidVolumeDirection.raise);
      expect(s.player.volumeNotifier.value, before + PlayerManager.remoteVolumeStep);

      await s.handler.androidAdjustRemoteVolume(AndroidVolumeDirection.lower);
      expect(s.player.volumeNotifier.value, before);

      await s.handler.androidAdjustRemoteVolume(AndroidVolumeDirection.same);
      expect(s.player.volumeNotifier.value, before);
    });

    test('[WA-08] 스피커 출력 중의 원격 볼륨 명령은 스피커 볼륨으로 전달된다', () async {
      s.soap.volume = 40;
      s.manager.selectedDeviceNotifier.value = remoteSpeaker();
      await pumpEventQueue();
      expect(s.player.volumeNotifier.value, 40);

      await s.handler.androidAdjustRemoteVolume(AndroidVolumeDirection.raise);
      await pumpEventQueue();

      expect(s.soap.lastVolume, 40 + PlayerManager.remoteVolumeStep);
    });

    test('[WA-09] 원격 볼륨 지정은 그 값으로 볼륨을 설정한다', () async {
      await s.handler.androidSetRemoteVolume(70);

      expect(s.player.volumeNotifier.value, 70);
      expect(channel.argumentsOf('setPhoneVolume').last, {'percent': 70});
    });
  });

  group('상태 알림', () {
    test('[WA-10] 만들어지면 곡 없음·정지 상태를 한 번 알린다', () {
      expect(s.state.processingState, AudioProcessingState.idle);
      expect(s.state.playing, isFalse);
    });

    test('[WA-11, WA-13] 재생 중이면 버튼은 이전·일시정지·다음이고 셋 모두 축약 알림에 보인다', () async {
      await startPlaying();

      expect(s.state.controls, [MediaControl.skipToPrevious, MediaControl.pause, MediaControl.skipToNext]);
      expect(s.state.playing, isTrue);
      expect(s.state.androidCompactActionIndices, [0, 1, 2]);
    });

    test('[WA-12, WA-13] 재생 중이 아니면 버튼은 이전·재생·다음이다', () async {
      await startPlaying();
      s.phone.controller.add(const BackendStateChanged(playing: false));

      expect(s.state.controls, [MediaControl.skipToPrevious, MediaControl.play, MediaControl.skipToNext]);
      expect(s.state.playing, isFalse);
      expect(s.state.androidCompactActionIndices, [0, 1, 2]);
    });

    test('[WA-14] 탐색할 수 있을 때만 탐색 동작을 알린다', () async {
      await startPlaying();
      expect(s.state.systemActions, contains(MediaAction.seek));

      s.player.canSeekNotifier.value = false;
      expect(s.state.systemActions, isNot(contains(MediaAction.seek)));
    });

    test('[WA-15] 곡이 없으면 idle, 버퍼링 중이면 buffering, 그 밖에는 ready로 알린다', () async {
      expect(s.state.processingState, AudioProcessingState.idle);

      await s.player.playTrack(playlist[0], queue: playlist, index: 0);
      s.phone.controller.add(const BackendStateChanged(playing: true, buffering: true));
      expect(s.state.processingState, AudioProcessingState.buffering);

      s.phone.controller.add(const BackendStateChanged(playing: true));
      expect(s.state.processingState, AudioProcessingState.ready);
    });

    test('[WA-16] 재생 위치가 바뀌면 그 위치를 알린다', () async {
      await startPlaying();

      s.phone.controller.add(const BackendPositionChanged(Duration(seconds: 12)));

      expect(s.state.updatePosition, const Duration(seconds: 12));
    });

    test('[WA-17] 대기열 위치는 대기열이 있을 때만 알린다', () async {
      expect(s.state.queueIndex, isNull);

      await startPlaying(index: 1);

      expect(s.state.queueIndex, 1);
    });

    test('[WA-18] 곡이 없으면 현재 곡 정보가 없다', () {
      expect(s.handler.mediaItem.value, isNull);
    });

    test('[WA-19] 현재 곡의 ID·제목·가수·앨범·길이·커버를 알린다', () async {
      final track = testTrack(
        '7',
        title: '제목',
        artistName: '가수 이름',
        albumTitle: '앨범 이름',
        coverUrl: 'https://resources.example.test/cover.jpg',
        durationSeconds: 205,
      );

      await s.player.playTrack(track, queue: [track], index: 0);

      final item = s.handler.mediaItem.value!;
      expect(item.id, '7');
      expect(item.title, '제목');
      expect(item.artist, '가수 이름');
      expect(item.album, '앨범 이름');
      expect(item.duration, const Duration(seconds: 205));
      expect(item.artUri, Uri.parse('https://resources.example.test/cover.jpg'));
    });

    test('[WA-19] 출력 기기가 알려준 길이가 있으면 그 길이를 쓰고, 커버가 없으면 커버 주소도 없다', () async {
      await startPlaying();
      expect(s.handler.mediaItem.value!.artUri, isNull);

      s.phone.controller.add(const BackendTrackStarted('1', duration: Duration(seconds: 200)));

      expect(s.handler.mediaItem.value!.duration, const Duration(seconds: 200));
    });

    test('[WA-19] 길이를 모르는 곡은 길이 없이 알린다', () async {
      final track = testTrack('8', durationSeconds: 0);

      await s.player.playTrack(track, queue: [track], index: 0);

      expect(s.handler.mediaItem.value!.duration, isNull);
    });

    test('[WA-20] 대기열이 바뀌면 같은 순서의 곡 목록을 알린다', () async {
      await startPlaying();

      expect(s.handler.queue.value.map((item) => item.id), ['1', '2', '3']);
      expect(s.handler.queue.value.first.duration, const Duration(seconds: 180));
    });

    test('[WA-21] 폰 스피커가 선택되어 있으면 로컬 재생으로 알린다', () {
      expect(s.handler.androidPlaybackInfo.value, isA<LocalAndroidPlaybackInfo>());
    });

    test('[WA-22] 원격 스피커가 선택되면 절대 볼륨 방식의 원격 재생으로 알린다', () async {
      s.soap.volume = 40;
      s.manager.selectedDeviceNotifier.value = remoteSpeaker();
      await pumpEventQueue();

      final info = s.handler.androidPlaybackInfo.value as RemoteAndroidPlaybackInfo;
      expect(info.volumeControlType, AndroidVolumeControlType.absolute);
      expect(info.maxVolume, 100);
      expect(info.volume, 40);
    });

    test('[WA-23] 선택 기기나 볼륨이 바뀔 때마다 재생 정보를 다시 알린다', () async {
      final infos = <AndroidPlaybackInfo>[];
      s.handler.androidPlaybackInfo.listen(infos.add);
      await pumpEventQueue();
      infos.clear();

      s.soap.volume = 40;
      s.manager.selectedDeviceNotifier.value = remoteSpeaker();
      await pumpEventQueue();
      // 기기가 바뀔 때 한 번, 스피커 볼륨(40)을 읽어 왔을 때 한 번
      expect(infos.whereType<RemoteAndroidPlaybackInfo>().map((i) => i.volume), [50, 40]);

      s.manager.selectedDeviceNotifier.value = DlnaDevice.localSpeaker;
      await pumpEventQueue();
      expect(infos.last, isA<LocalAndroidPlaybackInfo>());
    });
  });

  group('속성', () {
    property('[P-WA-1] 어떤 곡이든 현재 곡 정보의 ID·제목·가수·앨범이 곡과 같고, 길이와 커버는 값이 있을 때만 있다', () {
      forAll(tracks(), (track) async {
        final subject = _Subject();

        await subject.player.playTrack(track, queue: [track], index: 0);

        final item = subject.handler.mediaItem.value!;
        expect(item.id, track.id);
        expect(item.title, track.title);
        expect(item.artist, track.artistName);
        expect(item.album, track.albumTitle);
        expect(item.duration == null, track.durationSeconds <= 0, reason: '길이 ${track.durationSeconds}');
        if (item.duration != null) expect(item.duration!.inSeconds, track.durationSeconds);
        expect(item.artUri == null, track.coverUrl.isEmpty, reason: '커버 "${track.coverUrl}"');
      });
    });

    property('[P-WA-2] 어떤 곡 목록이든 알리는 대기열의 길이와 순서가 목록과 같다', () {
      forAll(trackLists(), (list) {
        final subject = _Subject();

        subject.player.setQueue(list);

        expect(subject.handler.queue.value.map((item) => item.id), list.map((t) => t.id));
      });
    });
  });
}
