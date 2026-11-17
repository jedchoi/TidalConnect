import 'dart:async';

import 'package:tidal_connect_lite/features/player/data/backends/playback_backend.dart';
import 'package:tidal_connect_lite/features/tidal_api/domain/models/media_item.dart';

/// 재생 요청을 기록하고, 테스트가 이벤트를 직접 흘려보낼 수 있는 가짜 출력 기기.
class FakeBackend implements PlaybackBackend {
  final controller = StreamController<BackendEvent>.broadcast(sync: true);
  final played = <String>[];
  Future<void> Function(MediaTrack track)? onPlay;

  /// `play` 밖의 명령 기록(순서대로): `pause`, `resume`, `seek:<초>`, `stop`.
  final commands = <String>[];

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
  Future<void> pause() async => commands.add('pause');
  @override
  Future<void> resume() async => commands.add('resume');
  @override
  Future<void> seek(Duration position) async => commands.add('seek:${position.inSeconds}');
  @override
  Future<void> stop() async => commands.add('stop');

  final nextRequests = <String?>[];
  @override
  Future<void> setNext(MediaTrack? track) async => nextRequests.add(track?.id);

  String? quality;
  @override
  Future<void> setAudioQuality(String quality) async {
    this.quality = quality;
  }
}
