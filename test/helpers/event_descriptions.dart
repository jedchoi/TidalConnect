import 'package:tidal_connect_lite/features/player/data/backends/playback_backend.dart';

/// [BackendEvent]를 한 줄 문자열로 바꾼다. 이벤트 순서를 한 번에 비교하는 데 쓴다.
///
/// - `state(playing)`, `state(playing,buffering)`, `state(stopped)`
/// - `position(12/180)`: 위치/길이(초). 길이를 모르면 `position(12/-)`
/// - `started(123)`, `ended(123)`, `error(DLNA_UNREACHABLE)`
///
/// 밀리초 단위 위치나 음질 같은 세부 필드는 필요한 테스트에서 따로 확인한다.
String describeEvent(BackendEvent event) => switch (event) {
      BackendStateChanged(:final playing, :final buffering) =>
        'state(${playing ? 'playing' : 'stopped'}${buffering ? ',buffering' : ''})',
      BackendPositionChanged(:final position, :final duration) =>
        'position(${position.inSeconds}/${duration?.inSeconds ?? '-'})',
      BackendTrackStarted(:final trackId) => 'started($trackId)',
      BackendTrackEnded(:final trackId) => 'ended($trackId)',
      BackendError(:final code) => 'error($code)',
    };

List<String> describeEvents(Iterable<BackendEvent> events) => events.map(describeEvent).toList();
