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

  /// 지금 스피커에 보낸 주소와, 갭리스로 미리 등록한 다음 곡.
  String? _currentUrl;
  _PreparedNext? _next;

  /// SetNextAVTransportURI를 거부한 스피커(UDN). 이후 이 스피커에는 등록을 시도하지 않는다.
  final Set<String> _noGaplessDevices = {};
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
    _next = null; // SetAVTransportURI가 스피커의 다음 곡 등록도 지운다
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
      quality: StreamQuality(audioQuality: info.audioQuality, bitDepth: info.bitDepth, sampleRate: info.sampleRate),
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
    _currentUrl = proxyUrl;
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
      final pos = results[1] as DlnaPosition?;
      if (_pollTimer == null || trackId != _trackId) return; // 그 사이 정지되었거나 곡이 바뀜
      if (pos != null && _checkGaplessTransition(pos.trackUri)) return; // 다음 확인부터 새 곡 기준

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
        final position = Duration(seconds: pos.progressSeconds);
        final durationSec = pos.durationSeconds;
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

  // ──────────────────────────────────────────────
  // 갭리스(SetNextAVTransportURI)
  // ──────────────────────────────────────────────

  @override
  Future<void> setNext(MediaTrack? track) => _serialize(() => _setNextOnSpeaker(track));

  Future<void> _setNextOnSpeaker(MediaTrack? track) async {
    final device = _dlna.selectedDevice;
    if (device.isLocalSpeaker || _noGaplessDevices.contains(device.udn)) return;
    if (track == null) {
      if (_next == null) return;
      _next = null;
      await _dlna.setNextOnSelectedDevice(streamUrl: '');
      return;
    }
    if (_next?.track.id == track.id) return;

    final info = await _api.getPlaybackInfo(track.id, quality: preferredQuality);
    if (info == null) return;
    final proxyUrl = await TidalSdkNativeBridge.registerTrackStream(
      trackId: track.id,
      directUrl: info.streamUrl,
      manifestXml: info.manifest,
      allowedHost: Uri.tryParse(device.locationUrl)?.host ?? '',
      mimeType: info.mimeType,
    );
    if (proxyUrl.isEmpty || _dlna.selectedDevice.udn != device.udn) return;

    final ok = await _dlna.setNextOnSelectedDevice(
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
    if (ok) {
      _next = _PreparedNext(track, proxyUrl, info);
      AppLogger.log('DLNA_BACKEND', '다음 곡 미리 등록: "${track.title}"', type: LogType.info);
    } else {
      // 지원하지 않는 렌더러. 곡이 끝나면 기존처럼 STOPPED를 보고 다음 곡을 보낸다.
      _noGaplessDevices.add(device.udn);
      _next = null;
      AppLogger.log('DLNA_BACKEND', '"${device.friendlyName}"은 SetNextAVTransportURI를 지원하지 않음', type: LogType.warning);
    }
  }

  /// 스피커가 재생 중인 주소가 미리 등록한 다음 곡이면, 그 곡으로 넘어간 것으로 처리한다.
  bool _checkGaplessTransition(String trackUri) {
    final next = _next;
    if (next == null || trackUri.isEmpty || trackUri == _currentUrl) return false;
    if (!_sameStreamUrl(trackUri, next.url)) return false;
    _next = null;
    _currentUrl = next.url;
    _trackId = next.track.id;
    _duration = next.track.durationSeconds > 0 ? Duration(seconds: next.track.durationSeconds) : null;
    _lastPosition = Duration.zero;
    _canSeek = !next.info.isDash;
    AppLogger.log('DLNA_BACKEND', '스피커가 다음 곡으로 넘어감: "${next.track.title}"', type: LogType.info);
    _events.add(BackendTrackStarted(
      next.track.id,
      duration: _duration,
      quality: StreamQuality(
        audioQuality: next.info.audioQuality,
        bitDepth: next.info.bitDepth,
        sampleRate: next.info.sampleRate,
      ),
    ));
    return true;
  }

  /// 렌더러가 주소의 호스트 표기를 바꿔 돌려주는 경우가 있어 경로와 쿼리로 비교한다.
  static bool _sameStreamUrl(String a, String b) {
    final ua = Uri.tryParse(a.trim());
    final ub = Uri.tryParse(b.trim());
    if (ua == null || ub == null) return a.trim() == b.trim();
    return ua.path == ub.path && ua.query == ub.query;
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
    _next = null;
    _currentUrl = null;
    await _dlna.stopCurrent();
    _events.add(const BackendStateChanged(playing: false));
  }

  void dispose() {
    _stopPolling();
    _events.close();
  }
}

class _PreparedNext {
  final MediaTrack track;
  final String url;
  final TidalPlaybackInfo info;
  const _PreparedNext(this.track, this.url, this.info);
}
