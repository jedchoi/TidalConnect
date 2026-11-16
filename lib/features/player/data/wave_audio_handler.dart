import 'package:audio_service/audio_service.dart';
import 'player_manager.dart';

/// 시스템 미디어 세션(잠금화면, 알림, 블루투스·이어폰 버튼)과 [PlayerManager]를 잇는다.
///
/// 명령은 PlayerManager로 넘기고, PlayerManager의 상태는 재생 상태·현재 곡·대기열로 내보낸다.
///
/// 오디오 포커스(전화, 다른 앱 재생)와 이어폰 분리(becoming noisy)는 별도로 처리하지 않는다.
/// TIDAL Player SDK가 내부 ExoPlayer에 `setAudioAttributes(attrs, handleAudioFocus = true)`와
/// `setHandleAudioBecomingNoisy(true)`를 설정해 폰 출력에서 이미 일시정지·재개하며,
/// 그 결과는 PlaybackStateChange 이벤트로 PlayerManager에 반영된다(중복 처리 방지).
/// DLNA 출력은 소리가 스피커에서 나므로 전화나 이어폰 분리에 반응하지 않는다.
class WaveAudioHandler extends BaseAudioHandler {
  final PlayerManager _player;

  WaveAudioHandler(this._player) {
    for (final listenable in [
      _player.isPlayingNotifier,
      _player.isBufferingNotifier,
      _player.progressSecondsNotifier,
      _player.queueIndexNotifier,
      _player.canSeekNotifier,
    ]) {
      listenable.addListener(_broadcastState);
    }
    _player.currentTrackNotifier.addListener(_broadcastMediaItem);
    _player.durationSecondsNotifier.addListener(_broadcastMediaItem);
    _player.queueNotifier.addListener(_broadcastQueue);
    _broadcastState();
  }

  void _broadcastState() {
    final playing = _player.isPlaying;
    final hasTrack = _player.currentTrack != null;
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      androidCompactActionIndices: const [0, 1, 2],
      systemActions: {
        if (_player.canSeekNotifier.value) MediaAction.seek,
      },
      processingState: !hasTrack
          ? AudioProcessingState.idle
          : (_player.isBufferingNotifier.value ? AudioProcessingState.buffering : AudioProcessingState.ready),
      playing: playing,
      updatePosition: Duration(seconds: _player.progressSeconds),
      queueIndex: _player.queueIndex >= 0 ? _player.queueIndex : null,
    ));
  }

  void _broadcastMediaItem() {
    final track = _player.currentTrack;
    if (track == null) {
      mediaItem.add(null);
      return;
    }
    final durationSec = _player.durationSeconds > 0 ? _player.durationSeconds : track.durationSeconds;
    mediaItem.add(MediaItem(
      id: track.id,
      title: track.title,
      artist: track.artistName,
      album: track.albumTitle,
      duration: durationSec > 0 ? Duration(seconds: durationSec) : null,
      artUri: track.coverUrl.isNotEmpty ? Uri.parse(track.coverUrl) : null,
    ));
  }

  void _broadcastQueue() {
    queue.add(_player.queue
        .map((t) => MediaItem(
              id: t.id,
              title: t.title,
              artist: t.artistName,
              album: t.albumTitle,
              duration: t.durationSeconds > 0 ? Duration(seconds: t.durationSeconds) : null,
              artUri: t.coverUrl.isNotEmpty ? Uri.parse(t.coverUrl) : null,
            ))
        .toList());
  }

  @override
  Future<void> play() => _player.resume();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async => _player.seekTo(position.inSeconds);

  @override
  Future<void> skipToNext() async => _player.skipToNext();

  @override
  Future<void> skipToPrevious() async => _player.skipToPrevious();

  @override
  Future<void> skipToQueueItem(int index) async => _player.playQueueIndex(index);
}
