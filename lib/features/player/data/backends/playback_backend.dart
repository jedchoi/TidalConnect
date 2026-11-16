import '../../../tidal_api/domain/models/media_item.dart';

/// 출력 기기(폰 / DLNA 스피커)가 보내는 재생 이벤트.
sealed class BackendEvent {
  const BackendEvent();
}

/// 재생 상태 변화. [buffering]은 재생을 원하지만 데이터를 기다리는 중이라는 뜻이다.
class BackendStateChanged extends BackendEvent {
  final bool playing;
  final bool buffering;
  const BackendStateChanged({required this.playing, this.buffering = false});
}

/// 현재 재생 위치. 길이를 알면 [duration]도 함께 보낸다.
class BackendPositionChanged extends BackendEvent {
  final Duration position;
  final Duration? duration;
  const BackendPositionChanged(this.position, {this.duration});
}

/// 곡 재생이 실제로 시작됨. 출력 기기가 알려준 길이와 음질 정보를 담는다.
class BackendTrackStarted extends BackendEvent {
  final String trackId;
  final Duration? duration;
  final StreamQuality? quality;
  const BackendTrackStarted(this.trackId, {this.duration, this.quality});
}

/// 곡이 끝까지 재생됨.
class BackendTrackEnded extends BackendEvent {
  final String trackId;
  const BackendTrackEnded(this.trackId);
}

class BackendError extends BackendEvent {
  final String code;
  final String message;
  const BackendError(this.code, this.message);
}

/// 실제로 재생 중인 스트림의 음질 정보.
class StreamQuality {
  final String audioQuality;
  final int? bitDepth;
  final int? sampleRate;
  final String? codec;
  final bool preview;

  const StreamQuality({
    required this.audioQuality,
    this.bitDepth,
    this.sampleRate,
    this.codec,
    this.preview = false,
  });
}

/// 재생을 시작하는 동안 더 새로운 재생 요청이 들어왔는지 알려주는 함수.
typedef IsCancelled = bool Function();

/// 출력 기기 하나를 제어하는 공통 인터페이스.
abstract class PlaybackBackend {
  Stream<BackendEvent> get events;

  /// 탐색(seek)이 가능한지. DASH 중계처럼 불가능한 경로가 있다.
  bool get canSeek;

  /// [track]을 [startPosition]부터 재생한다. 실패하면 예외를 던진다.
  /// 비동기 단계 사이마다 [isCancelled]를 확인해 더 새로운 요청이 있으면 조용히 멈춘다.
  Future<void> play(MediaTrack track, {Duration startPosition = Duration.zero, required IsCancelled isCancelled});

  Future<void> pause();
  Future<void> resume();
  Future<void> seek(Duration position);
  Future<void> stop();
}

/// 실패를 화면에 보여줄 수 있는 메시지와 함께 전달하는 예외.
class PlaybackException implements Exception {
  final String code;
  final String message;
  const PlaybackException(this.code, this.message);

  @override
  String toString() => 'PlaybackException($code): $message';
}
