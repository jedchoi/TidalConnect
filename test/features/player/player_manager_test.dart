import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tidal_connect_lite/features/auth/data/secure_storage_service.dart';
import 'package:tidal_connect_lite/features/auth/data/tidal_auth_repository.dart';
import 'package:tidal_connect_lite/features/player/data/backends/playback_backend.dart';
import 'package:tidal_connect_lite/features/player/data/player_manager.dart';
import 'package:tidal_connect_lite/features/tidal_api/domain/models/media_item.dart';
import '../../helpers/fakes.dart';

MediaTrack t(String id) => MediaTrack(
      id: id,
      title: 'Track $id',
      artistName: 'Artist',
      albumTitle: 'Album',
      coverUrl: '',
      durationSeconds: 180,
    );

/// 재생 요청을 기록하고, 테스트가 이벤트를 직접 흘려보낼 수 있는 가짜 출력 기기.
class FakeBackend implements PlaybackBackend {
  final controller = StreamController<BackendEvent>.broadcast(sync: true);
  final played = <String>[];
  Future<void> Function(MediaTrack track)? onPlay;

  @override
  Stream<BackendEvent> get events => controller.stream;

  @override
  bool get canSeek => true;

  @override
  Future<void> play(MediaTrack track,
      {Duration startPosition = Duration.zero, required IsCancelled isCancelled}) async {
    played.add(track.id);
    await onPlay?.call(track);
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> stop() async {}

  final nextRequests = <String?>[];
  @override
  Future<void> setNext(MediaTrack? track) async => nextRequests.add(track?.id);

  String? quality;
  @override
  Future<void> setAudioQuality(String quality) async {
    this.quality = quality;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeBackend phone;
  late FakeBackend dlna;
  late PlayerManager player;

  setUp(() {
    phone = FakeBackend();
    final auth = TidalAuthRepository(
      storageService: SecureStorageService(storage: FakeFlutterSecureStorage()),
      dio: Dio()
        ..httpClientAdapter =
            FakeAdapter((o) async => throw DioException.connectionError(requestOptions: o, reason: 'offline')),
      nativeSink: FakeNativeSink(),
    );
    dlna = FakeBackend();
    player = PlayerManager.forTesting()..configure(authRepository: auth, phone: phone, dlna: dlna);
  });

  test('음질 배지는 출력 기기가 알려준 실제 스트림 값으로 바뀐다', () async {
    await player.playTrack(t('1'), queue: [t('1')], index: 0);
    expect(player.qualityBadgeNotifier.value, '');

    phone.controller.add(const BackendTrackStarted(
      '1',
      quality: StreamQuality(audioQuality: 'HI_RES_LOSSLESS', bitDepth: 24, sampleRate: 192000),
    ));
    expect(player.qualityBadgeNotifier.value, 'Hi-Res FLAC · 24-bit / 192kHz');
    expect(player.isHiResNotifier.value, isTrue);
  });

  group('갭리스', () {
    test('곡이 시작되면 다음 곡을 미리 등록한다', () async {
      final tracks = [t('1'), t('2'), t('3')];
      await player.playTrack(tracks[0], queue: tracks, index: 0);
      expect(phone.nextRequests, isEmpty); // 시작 전에는 등록하지 않는다

      phone.controller.add(const BackendTrackStarted('1'));
      expect(phone.nextRequests, ['2']);
    });

    test('출력 기기가 다음 곡으로 넘어가면 다시 불러오지 않고 대기열만 옮긴다', () async {
      final tracks = [t('1'), t('2'), t('3')];
      await player.playTrack(tracks[0], queue: tracks, index: 0);
      phone.controller.add(const BackendTrackStarted('1'));

      phone.controller.add(const BackendTrackStarted('2'));

      expect(player.currentTrack!.id, '2');
      expect(player.queueIndex, 1);
      expect(phone.played, ['1']); // play를 다시 부르지 않음
      expect(phone.nextRequests, ['2', '3']);
    });

    test('셔플·반복을 바꾸면 이어질 곡을 다시 등록한다', () async {
      final tracks = [t('1'), t('2')];
      await player.playTrack(tracks[1], queue: tracks, index: 1);
      phone.controller.add(const BackendTrackStarted('2'));
      expect(phone.nextRequests, isEmpty); // 마지막 곡, 반복 없음 → 등록할 곡 없음

      player.toggleRepeat(); // 전체 반복
      expect(phone.nextRequests, ['1']);

      player.toggleRepeat(); // 한 곡 반복은 끝난 뒤 다시 재생하므로 등록을 지운다
      expect(phone.nextRequests, ['1', null]);
    });

    test('등록하지 않은 곡의 시작 이벤트는 무시한다', () async {
      await player.playTrack(t('1'), queue: [t('1'), t('2')], index: 0);
      phone.controller.add(const BackendTrackStarted('1'));
      phone.controller.add(const BackendTrackStarted('zzz'));
      expect(player.currentTrack!.id, '1');
    });
  });

  test('음질 설정은 폰과 스피커 출력 모두에 전달된다', () async {
    await player.setAudioQuality('HI_RES_LOSSLESS');
    expect(phone.quality, 'HI_RES_LOSSLESS');
    expect(dlna.quality, 'HI_RES_LOSSLESS');
  });

  test('an ended event moves to the next track in the queue', () async {
    final tracks = [t('1'), t('2'), t('3')];
    await player.playTrack(tracks[0], queue: tracks, index: 0);

    phone.controller.add(const BackendTrackEnded('1'));
    await Future<void>.delayed(Duration.zero);

    expect(phone.played, ['1', '2']);
    expect(player.currentTrack!.id, '2');
    expect(player.queueIndex, 1);
  });

  test('the last track ending without similar tracks leaves the player stopped', () async {
    await player.playTrack(t('9'), queue: [t('9')], index: 0);
    phone.controller.add(const BackendStateChanged(playing: true));

    phone.controller.add(const BackendTrackEnded('9'));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(player.isPlaying, isFalse);
  });

  test('a slow earlier request does not override a newer one', () async {
    final gate = Completer<void>();
    phone.onPlay = (track) async {
      if (track.id == 'slow') {
        await gate.future;
        throw const PlaybackException('X', 'late failure');
      }
    };

    final first = player.playTrack(t('slow'), queue: [t('slow'), t('fast')], index: 0);
    await player.playTrack(t('fast'), queue: [t('slow'), t('fast')], index: 1);
    gate.complete();
    await first;

    expect(player.currentTrack!.id, 'fast');
    expect(player.isPlaying, isTrue);
    expect(player.errorNotifier.value, isNull);
  });

  test('a failed start reports an error and clears the playing state', () async {
    phone.onPlay = (_) async => throw const PlaybackException('NO_STREAM', '스트림 없음');

    final ok = await player.playTrack(t('1'), queue: [t('1')], index: 0);

    expect(ok, isFalse);
    expect(player.isPlaying, isFalse);
    expect(player.errorNotifier.value!.message, '스트림 없음');
  });

  test('state events from the backend drive isPlaying', () async {
    await player.playTrack(t('1'), queue: [t('1')], index: 0);
    phone.controller.add(const BackendStateChanged(playing: false));
    expect(player.isPlaying, isFalse);
    phone.controller.add(const BackendPositionChanged(Duration(seconds: 42), duration: Duration(seconds: 200)));
    expect(player.progressSeconds, 42);
    expect(player.durationSeconds, 200);
  });
}
