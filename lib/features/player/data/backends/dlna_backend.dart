import 'dart:async';
import '../../../../core/native/tidal_sdk_native_bridge.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../auth/data/tidal_auth_repository.dart';
import '../../../dlna/data/dlna_manager.dart';
import '../../../tidal_api/data/tidal_api_client.dart';
import '../../../tidal_api/domain/models/media_item.dart';
import 'playback_backend.dart';

/// DLNA 스피커 출력. 스트림 정보를 받아 폰의 프록시에 등록하고, 스피커에 SOAP 명령을 보낸다.
class DlnaBackend implements PlaybackBackend {
  final TidalAuthRepository _auth;
  final TidalApiClient _api;
  final DlnaManager _dlna;

  final _events = StreamController<BackendEvent>.broadcast();

  // 스피커 상태 확인(1초 간격)
  static const _pollInterval = Duration(seconds: 1);
  static const _endTolerance = Duration(seconds: 3);
  static const _maxFailures = 3;

  Timer? _pollTimer;
  bool _polling = false;
  String? _trackId;
  Duration? _duration;
  Duration _lastPosition = Duration.zero;
  bool _sawPlaying = false;
  int _failures = 0;

  DlnaBackend({required TidalAuthRepository auth, required TidalApiClient api, required DlnaManager dlna})
      : _auth = auth,
        _api = api,
        _dlna = dlna;

  /// DLNA로 요청할 음질. LOSSLESS는 단일 FLAC 주소라 Range 요청과 탐색이 된다.
  /// HI_RES_LOSSLESS는 DASH로 와서 탐색이 안 되므로 사용자가 고를 때만 쓴다.
  String preferredQuality = 'LOSSLESS';

  @override
  Stream<BackendEvent> get events => _events.stream;

  @override
  bool get canSeek => true;

  @override
  Future<void> play(MediaTrack track, {Duration startPosition = Duration.zero, required IsCancelled isCancelled}) async {
    _stopPolling();
    // 폰 스피커와 동시에 소리가 나지 않게 폰 재생을 멈춘다.
    await TidalSdkNativeBridge.stopTrack();

    final token = await _auth.getValidUserToken();
    if (isCancelled()) return;
    if (token == null) {
      throw const PlaybackException('NOT_LOGGED_IN', '스피커로 재생하려면 TIDAL 로그인이 필요합니다.');
    }

    final info = await _api.getPlaybackInfo(track.id, token.accessToken, quality: preferredQuality);
    if (isCancelled()) return;
    if (info == null) {
      throw const PlaybackException('NO_STREAM', '이 곡의 스트림 정보를 받지 못했습니다.');
    }

    final device = _dlna.selectedDevice;
    final proxyUrl = await TidalSdkNativeBridge.registerTrackStream(
      trackId: track.id,
      directUrl: info.streamUrl,
      manifestXml: info.manifest,
      allowedHost: Uri.tryParse(device.locationUrl)?.host ?? '',
      mimeType: info.mimeType,
    );
    if (isCancelled()) return;
    if (proxyUrl.isEmpty) {
      throw const PlaybackException('PROXY_FAILED', '스피커용 스트림 주소를 만들지 못했습니다. Wi-Fi 연결을 확인하세요.');
    }

    _events.add(BackendTrackStarted(
      track.id,
      duration: track.durationSeconds > 0 ? Duration(seconds: track.durationSeconds) : null,
      quality: StreamQuality(audioQuality: info.audioQuality),
    ));

    AppLogger.log('DLNA_BACKEND', '스피커 재생 요청: "${device.friendlyName}"', type: LogType.network);
    final ok = await _dlna.playOnSelectedDevice(streamUrl: proxyUrl, title: track.title);
    if (isCancelled()) return;
    if (!ok) {
      throw PlaybackException('DLNA_PLAY_FAILED', '"${device.friendlyName}"에 재생 명령을 보내지 못했습니다.');
    }
    if (startPosition > Duration.zero) {
      await _dlna.seek(startPosition.inSeconds);
    }
    _startPolling(track);
    TidalSdkNativeBridge.setStreamingLock(true);
    _events.add(const BackendStateChanged(playing: true, buffering: true));
  }

  void _startPolling(MediaTrack track) {
    _stopPolling();
    _trackId = track.id;
    _duration = track.durationSeconds > 0 ? Duration(seconds: track.durationSeconds) : null;
    _lastPosition = Duration.zero;
    _sawPlaying = false;
    _failures = 0;
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  void _stopPolling() {
    if (_pollTimer != null) TidalSdkNativeBridge.setStreamingLock(false);
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// GetTransportInfo와 GetPositionInfo로 스피커 상태를 읽어 이벤트로 바꾼다.
  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    try {
      final trackId = _trackId;
      final state = await _dlna.getTransportState();
      final pos = await _dlna.syncPosition();
      if (_pollTimer == null || trackId != _trackId) return; // 그 사이 정지되었거나 곡이 바뀜

      if (state == null && pos == null) {
        _failures++;
        if (_failures >= _maxFailures) {
          _stopPolling();
          _events.add(const BackendStateChanged(playing: false));
          _events.add(const BackendError('DLNA_UNREACHABLE', '스피커가 응답하지 않습니다. 전원과 네트워크를 확인하세요.'));
        }
        return;
      }
      _failures = 0;

      if (pos != null) {
        final position = Duration(seconds: pos['progress'] ?? 0);
        final durationSec = pos['duration'] ?? 0;
        if (durationSec > 0) _duration = Duration(seconds: durationSec);
        if (position > Duration.zero) _lastPosition = position;
        _events.add(BackendPositionChanged(position, duration: _duration));
      }

      switch (state) {
        case 'PLAYING':
          _sawPlaying = true;
          _events.add(const BackendStateChanged(playing: true));
        case 'TRANSITIONING':
          _events.add(const BackendStateChanged(playing: true, buffering: true));
        case 'PAUSED_PLAYBACK':
          _events.add(const BackendStateChanged(playing: false));
        case 'STOPPED':
        case 'NO_MEDIA_PRESENT':
          if (!_sawPlaying) return; // 재생 시작 전의 일시적인 STOPPED
          _stopPolling();
          final duration = _duration;
          final nearEnd = duration == null || _lastPosition >= duration - _endTolerance;
          if (nearEnd && trackId != null) {
            _events.add(BackendTrackEnded(trackId));
          } else {
            // 스피커 쪽에서 직접 정지함
            _events.add(const BackendStateChanged(playing: false));
          }
      }
    } finally {
      _polling = false;
    }
  }

  @override
  Future<void> pause() async {
    if (!await _dlna.pauseCurrent()) {
      throw const PlaybackException('DLNA_PAUSE_FAILED', '스피커를 일시정지하지 못했습니다.');
    }
    _events.add(const BackendStateChanged(playing: false));
  }

  @override
  Future<void> resume() async {
    if (!await _dlna.resumeCurrent()) {
      throw const PlaybackException('DLNA_RESUME_FAILED', '스피커 재생을 다시 시작하지 못했습니다.');
    }
    _events.add(const BackendStateChanged(playing: true));
  }

  @override
  Future<void> seek(Duration position) async {
    await _dlna.seek(position.inSeconds);
  }

  @override
  Future<void> stop() async {
    _stopPolling();
    _trackId = null;
    await _dlna.stopCurrent();
    _events.add(const BackendStateChanged(playing: false));
  }

  void dispose() {
    _stopPolling();
    _events.close();
  }
}
