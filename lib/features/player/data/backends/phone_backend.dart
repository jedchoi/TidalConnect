import 'dart:async';
import '../../../../core/native/tidal_sdk_native_bridge.dart';
import '../../../tidal_api/domain/models/media_item.dart';
import 'playback_backend.dart';

/// 폰 스피커 출력. TIDAL 공식 Player SDK(네이티브)를 제어하고 그 이벤트를 변환한다.
class PhoneBackend implements PlaybackBackend {
  final _events = StreamController<BackendEvent>.broadcast();
  StreamSubscription<Map<String, dynamic>>? _nativeSub;

  String? _currentTrackId;
  Duration? _pendingSeek;
  Duration? _duration;

  PhoneBackend({Stream<Map<String, dynamic>>? nativeEvents}) {
    _nativeSub = (nativeEvents ?? TidalSdkNativeBridge.playerEvents).listen(_onNativeEvent, onError: (_) {});
  }

  @override
  Stream<BackendEvent> get events => _events.stream;

  @override
  bool get canSeek => true;

  void _onNativeEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'state':
        final state = event['state'] as String? ?? '';
        _events.add(BackendStateChanged(
          playing: state == 'PLAYING' || state == 'STALLED',
          buffering: state == 'STALLED',
        ));
        if (state == 'PLAYING') _applyPendingSeek();
      case 'position':
        final ms = (event['positionMs'] as num?)?.toInt() ?? 0;
        _events.add(BackendPositionChanged(Duration(milliseconds: ms), duration: _duration));
      case 'transition':
        final trackId = event['trackId']?.toString() ?? '';
        final durationMs = (event['durationMs'] as num?)?.toInt() ?? 0;
        _currentTrackId = trackId;
        _duration = durationMs > 0 ? Duration(milliseconds: durationMs) : null;
        _events.add(BackendTrackStarted(
          trackId,
          duration: _duration,
          quality: StreamQuality(
            audioQuality: event['audioQuality']?.toString() ?? '',
            bitDepth: (event['bitDepth'] as num?)?.toInt(),
            sampleRate: (event['sampleRate'] as num?)?.toInt(),
            codec: event['codec']?.toString(),
            preview: event['preview'] == true,
          ),
        ));
      case 'ended':
        _events.add(BackendTrackEnded(event['trackId']?.toString() ?? _currentTrackId ?? ''));
      case 'error':
        _events.add(BackendError(
          event['code']?.toString() ?? 'UNKNOWN',
          event['message']?.toString() ?? '재생 오류',
        ));
    }
  }

  void _applyPendingSeek() {
    final seekTo = _pendingSeek;
    if (seekTo == null) return;
    _pendingSeek = null;
    TidalSdkNativeBridge.seekTrack(seekTo.inMilliseconds);
  }

  @override
  Future<void> setAudioQuality(String quality) => TidalSdkNativeBridge.setAudioQuality(quality);

  /// SDK setNext로 다음 곡을 미리 불러 둔다. SDK가 넘어가면 transition 이벤트가 온다.
  @override
  Future<void> setNext(MediaTrack? track) => TidalSdkNativeBridge.setNextTrack(track?.id ?? '');

  @override
  Future<void> play(MediaTrack track, {Duration startPosition = Duration.zero, required IsCancelled isCancelled}) async {
    _currentTrackId = track.id;
    _duration = track.durationSeconds > 0 ? Duration(seconds: track.durationSeconds) : null;
    // SDK는 IDLE 상태에서 seek를 받지 않으므로 재생이 시작된 뒤에 적용한다.
    _pendingSeek = startPosition > Duration.zero ? startPosition : null;
    final ok = await TidalSdkNativeBridge.playTrack(trackId: track.id);
    if (!ok && !isCancelled()) {
      throw const PlaybackException('PHONE_PLAY_FAILED', '폰에서 재생을 시작하지 못했습니다.');
    }
  }

  @override
  Future<void> pause() async {
    if (!await TidalSdkNativeBridge.pauseTrack()) {
      throw const PlaybackException('PHONE_PAUSE_FAILED', '일시정지하지 못했습니다.');
    }
  }

  @override
  Future<void> resume() async {
    if (!await TidalSdkNativeBridge.resumeTrack()) {
      throw const PlaybackException('PHONE_RESUME_FAILED', '재생을 다시 시작하지 못했습니다.');
    }
  }

  @override
  Future<void> seek(Duration position) async {
    await TidalSdkNativeBridge.seekTrack(position.inMilliseconds);
  }

  @override
  Future<void> stop() async {
    _pendingSeek = null;
    await TidalSdkNativeBridge.stopTrack();
  }

  void dispose() {
    _nativeSub?.cancel();
    _events.close();
  }
}
