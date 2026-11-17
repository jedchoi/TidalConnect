import 'dart:async';
import '../../../../core/native/tidal_sdk_native_bridge.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../auth/data/tidal_auth_repository.dart';
import '../../../dlna/data/dlna_manager.dart';
import '../../../dlna/data/upnp_soap_client.dart';
import '../../../dlna/domain/models/dlna_device.dart';
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

  /// 지금 곡과 그 스트림 정보. DASH 곡의 탐색(다시 등록)에 쓴다. 재생한 곡이 없으면 null.
  MediaTrack? _track;
  TidalPlaybackInfo? _info;

  /// 지금 흐름이 곡의 어느 위치부터 시작하는지(초 단위로 버림). 처음부터면 0.
  Duration _startOffset = Duration.zero;

  /// 시작 오프셋이 있는 흐름에서 스피커가 알려 주는 위치의 기준.
  /// true면 곡 전체 기준(절대), false면 흐름의 처음이 0(상대), null이면 아직 정하지 않음.
  bool? _absolutePosition;

  /// pause()가 성공한 뒤 resume()이나 새 재생이 없었는지.
  bool _paused = false;

  /// DASH 곡의 탐색(다시 등록 · 스피커 명령 · 알림)이 진행 중인지. 그동안에는 폴링 차례를 건너뛴다.
  /// 탐색의 Stop 직후에 STOPPED를 보고 스피커 쪽 정지나 곡 끝으로 잘못 판정하지 않기 위해서다.
  bool _seeking = false;

  /// 폴링 흐름의 번호. 탐색으로 흐름이 바뀌면 그 전에 보낸 확인의 응답을 버리는 데 쓴다.
  int _pollGeneration = 0;

  // 위치 기준 판정(실기기 확인 전의 추정값, business-rules R-1)
  static const _absoluteMinOffset = Duration(seconds: 10);
  static const _absoluteSlack = Duration(seconds: 2);

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

  /// DLNA로 요청할 음질. LOSSLESS는 단일 FLAC 주소라 Range 요청과 SOAP Seek가 된다.
  /// HI_RES_LOSSLESS는 DASH로 와서 탐색할 때마다 다시 등록해 재생하므로 사용자가 고를 때만 쓴다.
  String preferredQuality = 'LOSSLESS';

  @override
  Future<void> setAudioQuality(String quality) async {
    preferredQuality = quality;
  }

  @override
  Stream<BackendEvent> get events => _events.stream;

  /// 단일 파일 곡은 SOAP Seek로, DASH 곡은 그 위치부터 다시 등록해 재생하는 방식으로 탐색한다.
  @override
  bool get canSeek => true;

  @override
  Future<void> play(MediaTrack track,
      {Duration startPosition = Duration.zero, required IsCancelled isCancelled}) async {
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
    final device = _dlna.selectedDevice;
    // DASH 곡은 시작 위치가 속한 세그먼트부터 받는다. 단일 파일 곡은 재생 명령 뒤에 Seek를 보낸다.
    final registration =
        await _register(track, info, device, startPosition: info.isDash ? startPosition : Duration.zero);
    final proxyUrl = registration.url;
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
      metadata: _metadataOf(track, info),
    );
    if (isCancelled()) return;
    if (!ok) {
      throw PlaybackException('DLNA_PLAY_FAILED', '"${device.friendlyName}"에 재생 명령을 보내지 못했습니다.');
    }
    _currentUrl = proxyUrl;
    _track = track;
    _info = info;
    _paused = false;
    _beginFlow(info.isDash ? registration.startOffset : Duration.zero);
    if (startPosition > Duration.zero && !info.isDash) {
      await _dlna.seek(startPosition.inSeconds);
    }
    _startPolling(track);
    TidalSdkNativeBridge.setStreamingLock(true);
    _events.add(const BackendStateChanged(playing: true, buffering: true));
  }

  /// 곡의 스트림을 폰의 프록시에 등록한다. 프록시는 [device]의 주소에서 오는 요청만 받는다.
  static Future<ProxyRegistration> _register(
    MediaTrack track,
    TidalPlaybackInfo info,
    DlnaDevice device, {
    Duration startPosition = Duration.zero,
  }) =>
      TidalSdkNativeBridge.registerTrackStream(
        trackId: track.id,
        directUrl: info.streamUrl,
        manifestXml: info.manifest,
        allowedHost: Uri.tryParse(device.locationUrl)?.host ?? '',
        mimeType: info.mimeType,
        startPosition: startPosition,
      );

  void _startPolling(MediaTrack track) {
    _stopPolling();
    _trackId = track.id;
    _duration = track.durationSeconds > 0 ? Duration(seconds: track.durationSeconds) : null;
    _lastPosition = _startOffset;
    _sawPlaying = false;
    _failures = 0;
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  /// 스피커가 새 흐름(새 곡, 갭리스로 넘어간 곡, 탐색으로 다시 등록한 주소)을 재생하기 시작할 때 부른다.
  /// [startOffset]은 그 흐름이 곡의 어느 위치부터인지다(초 단위로 버림). 위치 기준은 다시 정한다.
  void _beginFlow(Duration startOffset) {
    _startOffset = Duration(seconds: startOffset.inSeconds);
    _absolutePosition = null;
  }

  void _stopPolling() {
    if (_pollTimer != null) TidalSdkNativeBridge.setStreamingLock(false);
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// GetTransportInfo와 GetPositionInfo로 스피커 상태를 읽어 이벤트로 바꾼다.
  Future<void> _poll() async {
    if (_polling || _seeking) return;
    _polling = true;
    try {
      final trackId = _trackId;
      final generation = _pollGeneration;
      // 두 요청을 동시에 보내 한 번의 확인이 2초(타임아웃)를 넘지 않게 한다.
      // 스피커가 꺼지면 3회 연속 실패까지 약 6~7초 안에 오류를 보고한다.
      final results = await Future.wait([_dlna.getTransportState(), _dlna.syncPosition()]);
      final state = results[0] as String?;
      final pos = results[1] as DlnaPosition?;
      if (_pollTimer == null || trackId != _trackId) return; // 그 사이 정지되었거나 곡이 바뀜
      if (generation != _pollGeneration) return; // 그 사이 탐색으로 흐름이 바뀜
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
        final relTime = Duration(seconds: pos.progressSeconds);
        final Duration position;
        if (_startOffset == Duration.zero) {
          position = relTime;
          final durationSec = pos.durationSeconds;
          if (durationSec > 0) _duration = Duration(seconds: durationSec);
        } else {
          // 중간부터 시작한 흐름: 렌더러의 길이는 남은 흐름의 길이일 수 있어 쓰지 않는다.
          position = _correctedPosition(relTime);
        }
        if (relTime > Duration.zero) _lastPosition = position;
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

  /// 시작 오프셋이 있는 흐름에서 스피커가 알려 준 [relTime]을 곡 전체 기준 위치로 바꾼다.
  /// 렌더러에 따라 흐름의 처음을 0으로 세기도(상대), 곡 전체 기준 시각을 알려 주기도(절대) 한다.
  /// 0보다 큰 첫 값으로 기준을 한 번 정하고 그 흐름이 끝날 때까지 바꾸지 않는다.
  Duration _correctedPosition(Duration relTime) {
    final offset = _startOffset;
    var absolute = _absolutePosition;
    if (absolute == null) {
      if (relTime == Duration.zero) return offset;
      absolute = offset >= _absoluteMinOffset && relTime >= offset - _absoluteSlack;
      _absolutePosition = absolute;
      AppLogger.log(
        'DLNA_BACKEND',
        '위치 기준: ${absolute ? '절대' : '상대'} (RelTime ${relTime.inSeconds}초, 시작 오프셋 ${offset.inSeconds}초)',
        type: LogType.info,
      );
    }
    return absolute ? relTime : offset + relTime;
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
    final proxyUrl = (await _register(track, info, device)).url;
    if (proxyUrl.isEmpty || _dlna.selectedDevice.udn != device.udn) return;

    final ok = await _dlna.setNextOnSelectedDevice(
      streamUrl: proxyUrl,
      metadata: _metadataOf(track, info),
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
    _track = next.track;
    _info = next.info;
    _beginFlow(Duration.zero);
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
    _paused = true;
    _events.add(const BackendStateChanged(playing: false));
  }

  @override
  Future<void> resume() async {
    if (!await _dlna.resumeCurrent()) {
      throw const PlaybackException('DLNA_RESUME_FAILED', '스피커 재생을 다시 시작하지 못했습니다.');
    }
    _paused = false;
    _events.add(const BackendStateChanged(playing: true));
  }

  @override
  Future<void> seek(Duration position) async {
    if (_info?.isDash ?? false) {
      // 스피커 명령이 play · setNext와 섞이지 않게 같은 줄에 세운다.
      await _serialize(() => _seekDash(position));
    } else {
      await _dlna.seek(position.inSeconds);
    }
  }

  /// DASH 곡의 탐색. 이어 붙인 흐름은 스피커가 탐색할 수 없으므로,
  /// 그 위치가 속한 세그먼트부터 다시 등록해 새 주소로 재생한다.
  Future<void> _seekDash(Duration position) async {
    final track = _track;
    final info = _info;
    if (track == null || info == null || !info.isDash) {
      // 차례를 기다리는 사이 곡이 바뀌거나 정지됨
      await _dlna.seek(position.inSeconds);
      return;
    }
    _seeking = true;
    try {
      await _reregisterAndPlay(track, info, position);
    } finally {
      _seeking = false;
    }
  }

  Future<void> _reregisterAndPlay(MediaTrack track, TidalPlaybackInfo info, Duration position) async {
    final device = _dlna.selectedDevice;
    final registration = await _register(track, info, device, startPosition: position);
    AppLogger.log(
      'DLNA_BACKEND',
      'DASH 탐색 요청: ${position.inMilliseconds}ms → 시작 오프셋 ${registration.startOffset.inMilliseconds}ms'
          '${registration.url.isEmpty ? ' (등록 실패)' : ''}',
      type: LogType.network,
    );
    if (registration.url.isEmpty) {
      throw const PlaybackException('PROXY_FAILED', '스피커용 스트림 주소를 만들지 못했습니다. Wi-Fi 연결을 확인하세요.');
    }
    final ok = await _dlna.playOnSelectedDevice(streamUrl: registration.url, metadata: _metadataOf(track, info));
    if (!ok) {
      throw PlaybackException('DLNA_PLAY_FAILED', '"${device.friendlyName}"에 재생 명령을 보내지 못했습니다.');
    }
    _currentUrl = registration.url;
    _beginFlow(registration.startOffset);

    // 재생 명령(SetAVTransportURI)이 스피커의 다음 곡 등록을 지우므로 다시 보낸다.
    final next = _next;
    if (next != null) {
      final nextOk = await _dlna.setNextOnSelectedDevice(
        streamUrl: next.url,
        metadata: _metadataOf(next.track, next.info),
      );
      if (!nextOk) _next = null;
    }
    if (_paused) await _dlna.pauseCurrent();

    // 폴링을 새 흐름 기준으로 다시 시작한다. 스트리밍 잠금은 켜진 채로 둔다.
    // (_stopPolling은 잠금을 풀기 때문에 타이머만 직접 바꾼다.)
    if (_pollTimer == null) TidalSdkNativeBridge.setStreamingLock(true);
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollGeneration++;
    _startPolling(track);
    _events.add(BackendPositionChanged(_startOffset, duration: _duration));
    _events.add(_paused
        ? const BackendStateChanged(playing: false)
        : const BackendStateChanged(playing: true, buffering: true));
  }

  /// 스피커에 보내는 곡 정보(DIDL-Lite). 재생 · 다음 곡 등록 · 탐색이 같은 값을 보낸다.
  static DidlMetadata _metadataOf(MediaTrack track, TidalPlaybackInfo info) => DidlMetadata(
        title: track.title,
        artist: track.artistName,
        album: track.albumTitle,
        albumArtUri: track.coverUrl,
        durationSeconds: track.durationSeconds,
        mimeType: info.mimeType,
      );

  @override
  Future<void> stop() async {
    _stopPolling();
    _trackId = null;
    _next = null;
    _currentUrl = null;
    _track = null;
    _info = null;
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
