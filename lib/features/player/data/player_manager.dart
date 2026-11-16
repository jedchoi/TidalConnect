import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/native/tidal_sdk_native_bridge.dart';
import '../../../core/utils/app_logger.dart';
import '../../auth/data/tidal_auth_repository.dart';
import '../../dlna/data/dlna_manager.dart';
import '../../dlna/domain/models/dlna_device.dart';
import '../../tidal_api/data/tidal_api_client.dart';
import '../../tidal_api/domain/models/media_item.dart';
import '../../volume/data/hardware_volume_service.dart';
import '../domain/play_queue.dart';
import 'backends/dlna_backend.dart';
import 'backends/phone_backend.dart';
import 'backends/playback_backend.dart';

export '../domain/play_queue.dart' show PlaybackRepeatMode;

/// 재생 상태의 단일 출처.
///
/// 화면은 아래 notifier만 구독한다. 재생 상태·위치·곡 종료는 출력 기기(백엔드)가 보낸 이벤트로만 갱신하며,
/// 타이머로 추정하지 않는다.
class PlayerManager {
  static final PlayerManager instance = PlayerManager._internal();
  PlayerManager._internal();

  late TidalAuthRepository _authRepo;
  final TidalApiClient _apiClient = TidalApiClient();
  final DlnaManager _dlnaManager = DlnaManager.instance;
  final PlayQueue _queue = PlayQueue();

  late final PlaybackBackend _phone;
  late final PlaybackBackend _dlna;
  bool _configured = false;

  final ValueNotifier<MediaTrack?> currentTrackNotifier = ValueNotifier(null);

  /// 재생 중(또는 재생하려고 버퍼링 중)인지.
  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier(false);

  /// 데이터를 기다리는 중인지.
  final ValueNotifier<bool> isBufferingNotifier = ValueNotifier(false);
  final ValueNotifier<int> progressSecondsNotifier = ValueNotifier(0);
  final ValueNotifier<int> durationSecondsNotifier = ValueNotifier(0);
  final ValueNotifier<String> qualityBadgeNotifier = ValueNotifier('');
  final ValueNotifier<bool> isShuffleNotifier = ValueNotifier(false);
  final ValueNotifier<PlaybackRepeatMode> repeatModeNotifier = ValueNotifier(PlaybackRepeatMode.off);
  final ValueNotifier<bool> canSeekNotifier = ValueNotifier(true);

  final ValueNotifier<List<MediaTrack>> queueNotifier = ValueNotifier(const []);
  final ValueNotifier<int> queueIndexNotifier = ValueNotifier(-1);

  /// 통합 볼륨 (0~100)
  final ValueNotifier<int> volumeNotifier = ValueNotifier(50);

  /// 가장 최근 재생 요청의 순번. 오래된 요청의 비동기 결과를 버리는 데 쓴다.
  int _requestSeq = 0;

  MediaTrack? get currentTrack => currentTrackNotifier.value;
  bool get isPlaying => isPlayingNotifier.value;
  int get progressSeconds => progressSecondsNotifier.value;
  int get durationSeconds => durationSecondsNotifier.value;
  bool get isShuffle => isShuffleNotifier.value;
  PlaybackRepeatMode get repeatMode => repeatModeNotifier.value;
  List<MediaTrack> get queue => _queue.tracks;
  int get queueIndex => _queue.index;

  PlaybackBackend get _backend => _dlnaManager.selectedDevice.isLocalSpeaker ? _phone : _dlna;

  /// 앱 시작 시 공유 인증 저장소를 주입하고 출력 기기 백엔드를 만든다.
  void configure({required TidalAuthRepository authRepository, PlaybackBackend? phone, PlaybackBackend? dlna}) {
    if (_configured) return;
    _configured = true;
    _authRepo = authRepository;
    _phone = phone ?? PhoneBackend();
    _dlna = dlna ?? DlnaBackend(auth: authRepository, api: _apiClient, dlna: _dlnaManager);
    _phone.events.listen((e) => _onBackendEvent(_phone, e));
    _dlna.events.listen((e) => _onBackendEvent(_dlna, e));

    _dlnaManager.selectedDeviceNotifier.addListener(_onOutputDeviceChanged);
    HardwareVolumeService.setShowSystemUI(_dlnaManager.selectedDevice.isLocalSpeaker);
    syncVolumeFromDevice();
  }

  // ──────────────────────────────────────────────
  // 백엔드 이벤트
  // ──────────────────────────────────────────────

  void _onBackendEvent(PlaybackBackend source, BackendEvent event) {
    if (!identical(source, _backend)) return; // 현재 출력 기기가 아닌 쪽의 늦은 이벤트
    switch (event) {
      case BackendStateChanged(:final playing, :final buffering):
        isPlayingNotifier.value = playing;
        isBufferingNotifier.value = buffering;
      case BackendPositionChanged(:final position, :final duration):
        progressSecondsNotifier.value = position.inSeconds;
        if (duration != null && duration > Duration.zero) {
          durationSecondsNotifier.value = duration.inSeconds;
        }
      case BackendTrackStarted(:final duration, :final quality):
        if (duration != null && duration > Duration.zero) {
          durationSecondsNotifier.value = duration.inSeconds;
        }
        if (quality != null) _updateQualityBadge(quality);
      case BackendTrackEnded(:final trackId):
        if (trackId.isEmpty || trackId == currentTrack?.id) _onTrackEnded();
      case BackendError(:final code, :final message):
        AppLogger.log('PLAYER', '출력 기기 오류 [$code]: $message', type: LogType.error);
        isPlayingNotifier.value = false;
        isBufferingNotifier.value = false;
    }
  }

  Future<void> _onTrackEnded() async {
    AppLogger.log('PLAYER', '곡 재생 완료 -> 다음 곡', type: LogType.info);
    final next = _queue.next(auto: true);
    if (next != null) {
      _notifyQueue();
      await _start(next);
      return;
    }
    // 대기열 끝: 유사곡을 붙여 이어서 재생하고, 붙일 곡이 없으면 정지 상태로 둔다.
    final current = currentTrack;
    if (current != null && await _appendSimilarTracks(current.id) > 0) {
      final appended = _queue.next();
      if (appended != null) {
        _notifyQueue();
        await _start(appended);
        return;
      }
    }
    isPlayingNotifier.value = false;
    isBufferingNotifier.value = false;
    progressSecondsNotifier.value = 0;
    TidalSdkNativeBridge.stopForegroundService();
  }

  // ──────────────────────────────────────────────
  // 재생
  // ──────────────────────────────────────────────

  /// 곡 재생. [queue]가 주어지면 대기열을 그 목록으로 바꾼다.
  /// 주어지지 않으면 현재 대기열에서 곡을 찾고, 없으면 그 곡 하나로 대기열을 만들고 유사곡을 붙인다.
  Future<bool> playTrack(MediaTrack track, {List<MediaTrack>? queue, int? index}) async {
    if (queue != null) {
      _queue.setTracks(queue, startIndex: index ?? queue.indexWhere((t) => t.id == track.id).clamp(0, queue.length));
    } else if (_queue.jumpToTrack(track.id) == null) {
      _queue.setSingle(track);
      _appendSimilarTracks(track.id);
    }
    _notifyQueue();
    return _start(_queue.current ?? track);
  }

  /// 대기열(플레이리스트/앨범 트랙 목록)을 설정한다. 재생은 [playTrack]으로 시작한다.
  void setQueue(List<MediaTrack> tracks, {int startIndex = 0}) {
    _queue.setTracks(tracks, startIndex: startIndex);
    _notifyQueue();
  }

  /// 대기열의 [index]번째 곡(재생 순서 기준)을 재생한다.
  void playQueueIndex(int index) {
    final track = _queue.jumpTo(index);
    if (track == null) return;
    _notifyQueue();
    _start(track);
  }

  Future<bool> _start(MediaTrack track, {Duration startPosition = Duration.zero}) async {
    final seq = ++_requestSeq;
    bool isCancelled() => seq != _requestSeq;

    currentTrackNotifier.value = track;
    progressSecondsNotifier.value = startPosition.inSeconds;
    durationSecondsNotifier.value = track.durationSeconds;
    isPlayingNotifier.value = true;
    isBufferingNotifier.value = true;
    _updateQualityBadge(StreamQuality(audioQuality: track.audioQuality));

    AppLogger.log('PLAYER', '재생 요청: "${track.title}" - ${track.artistName} (${track.id})', type: LogType.info);
    try {
      await _backend.play(track, startPosition: startPosition, isCancelled: isCancelled);
      if (isCancelled()) return false;
      // 백그라운드 재생 유지(알림 + WakeLock/WifiLock)
      TidalSdkNativeBridge.startForegroundService(title: track.title, artist: track.artistName);
      return true;
    } catch (e) {
      if (isCancelled()) return false;
      final message = e is PlaybackException ? e.message : '재생을 시작하지 못했습니다.';
      AppLogger.log('PLAYER', '재생 실패: $e', type: LogType.error);
      isPlayingNotifier.value = false;
      isBufferingNotifier.value = false;
      _reportError(message);
      return false;
    }
  }

  void _reportError(String message) {
    AppLogger.log('PLAYER', message, type: LogType.error);
  }

  /// 유사곡을 대기열 끝에 붙인다. 붙인 곡 수를 돌려준다.
  Future<int> _appendSimilarTracks(String trackId) async {
    try {
      final accessToken = await _authRepo.getCatalogToken();
      if (accessToken == null) return 0;
      final similars = await _apiClient.getSimilarTracks(trackId, accessToken, limit: 30);
      final added = _queue.append(similars);
      if (added > 0) {
        _notifyQueue();
        AppLogger.log('PLAYER', '연관 추천곡 $added개 대기열에 추가', type: LogType.success);
      }
      return added;
    } catch (e) {
      AppLogger.log('PLAYER', '연관 추천곡 조회 실패: $e', type: LogType.warning);
      return 0;
    }
  }

  void togglePlayPause() {
    if (currentTrack == null) return;
    if (isPlaying) {
      pause();
    } else {
      resume();
    }
  }

  Future<void> pause() async {
    if (currentTrack == null) return;
    try {
      await _backend.pause();
      isPlayingNotifier.value = false;
      isBufferingNotifier.value = false;
    } catch (e) {
      _reportError(e is PlaybackException ? e.message : '일시정지하지 못했습니다.');
    }
  }

  Future<void> resume() async {
    final track = currentTrack;
    if (track == null) return;
    try {
      await _backend.resume();
      isPlayingNotifier.value = true;
    } catch (e) {
      _reportError(e is PlaybackException ? e.message : '재생을 다시 시작하지 못했습니다.');
    }
  }

  /// 재생 위치 탐색(초).
  void seekTo(int seconds) {
    if (!canSeekNotifier.value) return;
    final max = durationSecondsNotifier.value;
    final clamped = max > 0 ? seconds.clamp(0, max) : (seconds < 0 ? 0 : seconds);
    progressSecondsNotifier.value = clamped;
    _backend.seek(Duration(seconds: clamped));
  }

  Future<void> stop() async {
    _requestSeq++; // 진행 중인 재생 요청 취소
    isPlayingNotifier.value = false;
    isBufferingNotifier.value = false;
    progressSecondsNotifier.value = 0;
    TidalSdkNativeBridge.stopForegroundService();
    await _backend.stop();
  }

  void skipToNext() {
    final next = _queue.next();
    if (next != null) {
      _notifyQueue();
      _start(next);
      return;
    }
    // 대기열 끝에서 다음 곡: 유사곡을 붙여 이어간다.
    final current = currentTrack;
    if (current == null) return;
    _appendSimilarTracks(current.id).then((added) {
      final appended = added > 0 ? _queue.next() : null;
      if (appended != null) {
        _notifyQueue();
        _start(appended);
      }
    });
  }

  void skipToPrevious() {
    if (progressSecondsNotifier.value > 3) {
      seekTo(0);
      return;
    }
    final previous = _queue.previous();
    if (previous != null) {
      _notifyQueue();
      _start(previous);
    } else {
      seekTo(0);
    }
  }

  void toggleShuffle() {
    _queue.setShuffle(!_queue.shuffle);
    isShuffleNotifier.value = _queue.shuffle;
    _notifyQueue();
  }

  void toggleRepeat() {
    repeatModeNotifier.value = _queue.cycleRepeat();
  }

  void _notifyQueue() {
    queueNotifier.value = _queue.tracks;
    queueIndexNotifier.value = _queue.index;
  }

  void _updateQualityBadge(StreamQuality quality) {
    final q = quality.audioQuality.toUpperCase();
    if (q.contains('HI_RES') || q.contains('HIRES') || q.contains('MAX')) {
      qualityBadgeNotifier.value = 'MAX';
    } else if (q.contains('LOSSLESS')) {
      qualityBadgeNotifier.value = 'FLAC';
    } else if (q.contains('HIGH')) {
      qualityBadgeNotifier.value = 'AAC 320kbps';
    } else if (q.contains('LOW')) {
      qualityBadgeNotifier.value = 'AAC 96kbps';
    } else {
      qualityBadgeNotifier.value = '';
    }
  }

  // ──────────────────────────────────────────────
  // 출력 기기
  // ──────────────────────────────────────────────

  /// 출력 기기 전환.
  Future<void> switchPlaybackDevice(DlnaDevice newDevice) async {
    final currentDevice = _dlnaManager.selectedDevice;
    if (currentDevice.udn == newDevice.udn) return;
    AppLogger.log('PLAYER', '출력 기기 전환: "${currentDevice.friendlyName}" → "${newDevice.friendlyName}"', type: LogType.info);

    final track = currentTrack;
    final wasPlaying = isPlaying;
    await _backend.stop();
    _dlnaManager.selectDevice(newDevice);
    if (wasPlaying && track != null) {
      await _start(track);
    }
  }

  // ──────────────────────────────────────────────
  // 볼륨
  // ──────────────────────────────────────────────

  /// 원격 스피커의 실제 볼륨을 읽기 전에는 SetVolume을 보내지 않는다(볼륨 급변 방지).
  bool _remoteVolumeKnown = false;
  int? _lastPhoneVolume;
  DateTime _lastRemoteVolumeSentAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _remoteVolumeInterval = Duration(milliseconds: 200);
  static const int remoteVolumeStep = 2;

  void _onOutputDeviceChanged() {
    _remoteVolumeKnown = false;
    HardwareVolumeService.setShowSystemUI(_dlnaManager.selectedDevice.isLocalSpeaker);
    syncVolumeFromDevice();
  }

  /// 현재 출력 기기의 볼륨을 읽어 [volumeNotifier]에 반영한다.
  Future<void> syncVolumeFromDevice() async {
    final device = _dlnaManager.selectedDevice;
    if (device.isLocalSpeaker) {
      final phone = await HardwareVolumeService.getPhoneVolume();
      if (phone != null) volumeNotifier.value = phone;
      return;
    }
    final volume = await _dlnaManager.fetchVolume();
    if (_dlnaManager.selectedDevice.udn != device.udn) return; // 그 사이 기기가 바뀜
    if (volume != null) {
      volumeNotifier.value = volume;
      _remoteVolumeKnown = true;
      AppLogger.log('PLAYER', '스피커 현재 볼륨 동기화: $volume', type: LogType.info);
    } else {
      AppLogger.log('PLAYER', '스피커 볼륨을 읽지 못해 볼륨 제어를 보류', type: LogType.warning);
    }
  }

  /// 폰 미디어 볼륨이 바뀌었을 때(볼륨 키) 호출된다.
  ///
  /// 폰으로 재생 중이면 그 값을 그대로 쓴다. 스피커로 재생 중이면 폰 볼륨의 절대값을 보내지 않고
  /// 올라갔는지 내려갔는지만 보고 스피커 볼륨을 [remoteVolumeStep]씩 바꾼다.
  /// 폰 볼륨이 0이나 100에 닿으면 더 움직이지 않는 한계가 있다(4단계에서 미디어 세션으로 대체).
  void onPhoneVolumeChanged(int phonePercent) {
    final previous = _lastPhoneVolume;
    _lastPhoneVolume = phonePercent;
    if (_dlnaManager.selectedDevice.isLocalSpeaker) {
      volumeNotifier.value = phonePercent;
      return;
    }
    if (previous == null || previous == phonePercent) return;
    final direction = phonePercent > previous ? 1 : -1;
    setVolume(volumeNotifier.value + direction * remoteVolumeStep);
  }

  /// 볼륨 설정 (0~100).
  ///
  /// 폰 출력이면 폰 미디어 볼륨을 바꾼다. 스피커 출력이면 슬라이더를 끄는 동안
  /// 200ms에 한 번만 보내고, [isFinal]이 true(손을 뗐을 때)면 마지막 값을 반드시 보낸다.
  void setVolume(int volumePercent, {bool isFinal = true}) {
    final clamped = volumePercent.clamp(0, 100);
    if (_dlnaManager.selectedDevice.isLocalSpeaker) {
      volumeNotifier.value = clamped;
      HardwareVolumeService.setPhoneVolume(clamped);
      return;
    }
    if (!_remoteVolumeKnown) {
      syncVolumeFromDevice();
      return;
    }
    volumeNotifier.value = clamped;
    final now = DateTime.now();
    if (!isFinal && now.difference(_lastRemoteVolumeSentAt) < _remoteVolumeInterval) return;
    _lastRemoteVolumeSentAt = now;
    _dlnaManager.setVolume(clamped);
  }
}
