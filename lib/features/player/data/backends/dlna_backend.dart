import 'dart:async';
import '../../../../core/native/tidal_sdk_native_bridge.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../auth/data/tidal_auth_repository.dart';
import '../../../dlna/data/dlna_manager.dart';
import '../../../dlna/data/upnp_soap_client.dart';
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
        _dlna = dlna {
    TidalSdkNativeBridge.setStreamRefresher(_refreshStream);
  }

  /// 서명 주소 만료 시 네이티브 프록시가 호출한다.
  Future<Map<String, Object>?> _refreshStream(String trackId) async {
    final token = await _auth.getValidUserToken();
    if (token == null) return null;
    final info = await _api.getPlaybackInfo(trackId, quality: preferredQuality);
    if (info == null) return null;
    AppLogger.log('DLNA_BACKEND', '만료된 스트림 주소 재발급 (TrackID: $trackId)', type: LogType.info);
    return {'directUrl': info.streamUrl, 'manifestXml': info.manifest, 'mimeType': info.mimeType};
  }

  /// DLNA로 요청할 음질. LOSSLESS는 단일 FLAC 주소라 Range 요청과 탐색이 된다.
  /// HI_RES_LOSSLESS는 DASH로 와서 탐색이 안 되므로 사용자가 고를 때만 쓴다.
  String preferredQuality = 'LOSSLESS';

  @override
  Future<void> setAudioQuality(String quality) async {
    preferredQuality = quality;
  }

  @override
  Stream<BackendEvent> get events => _events.stream;

  /// DASH 중계는 세그먼트를 이어 붙인 스트림이라 탐색할 수 없다.
  bool _canSeek = true;

  @override
  bool get canSeek => _canSeek;

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

    final info = await _api.getPlaybackInfo(track.id, quality: preferredQuality);
    if (isCancelled()) return;
    if (info == null) {
      throw const PlaybackException('NO_STREAM', '이 곡의 스트림 정보를 받지 못했습니다.');
    }

    // 스피커에 보내는 명령(등록·Stop·SetURI·Play)은 한 번에 하나씩 보낸다.
    // 곡을 빠르게 바꿔도 이전 요청의 SetAVTransportURI가 나중 요청 뒤에 도착하지 않는다.
    await _serialize(() => _sendToSpeaker(track, info, startPosition, isCancelled));
  }

  Future<void> _commandChain = Future<void>.value();

  Future<void> _serialize(Future<void> Function() action) {
    final next = _commandChain.then((_) => action());
    _commandChain = next.catchError((_) {});
    return next;
  }

  Future<void> _sendToSpeaker(
    MediaTrack track,
    TidalPlaybackInfo info,
    Duration startPosition,
    IsCancelled isCancelled,
  ) async {
    if (isCancelled()) return;
    _canSeek = !info.isDash;
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
    final ok = await _dlna.playOnSelectedDevice(
      streamUrl: proxyUrl,
      metadata: DidlMetadata(
        title: track.title,
        artist: track.artistName,
        album: track.albumTitle,
        albumArtUri: track.coverUrl,
        durationSeconds: track.durationSeconds,
        mimeType: info.mimeType,
      ),
    );
    if (isCancelled()) return;
    if (!ok) {
      throw PlaybackException('DLNA_PLAY_FAILED', '"${device.friendlyName}"에 재생 명령을 보내지 못했습니다.');
    }
    if (startPosition > Duration.zero && _canSeek) {
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
      // 두 요청을 동시에 보내 한 번의 확인이 2초(타임아웃)를 넘지 않게 한다.
      // 스피커가 꺼지면 3회 연속 실패까지 약 6~7초 안에 오류를 보고한다.
      final results = await Future.wait([_dlna.getTransportState(), _dlna.syncPosition()]);
      final state = results[0] as String?;
      final pos = results[1] as Map<String, int>?;
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
