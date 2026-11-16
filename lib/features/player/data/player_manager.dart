import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../../core/native/tidal_sdk_native_bridge.dart';
import '../../../core/utils/app_logger.dart';
import '../../auth/data/tidal_auth_repository.dart';
import '../../dlna/data/dlna_manager.dart';
import '../../dlna/domain/models/dlna_device.dart';
import '../../tidal_api/data/tidal_api_client.dart';
import '../../tidal_api/domain/models/media_item.dart';
import '../../volume/data/hardware_volume_service.dart';

enum PlaybackRepeatMode { off, all, one }

class PlayerManager {
  static final PlayerManager instance = PlayerManager._internal();
  PlayerManager._internal();

  late TidalAuthRepository _authRepo;

  /// 앱 시작 시 공유 인증 저장소를 주입한다.
  void configure({required TidalAuthRepository authRepository}) {
    _authRepo = authRepository;
    _dlnaManager.selectedDeviceNotifier.addListener(_onOutputDeviceChanged);
    HardwareVolumeService.setShowSystemUI(_dlnaManager.selectedDevice.isLocalSpeaker);
    syncVolumeFromDevice();
  }

  /// 원격 스피커의 실제 볼륨을 읽기 전에는 SetVolume을 보내지 않는다(볼륨 급변 방지).
  bool _remoteVolumeKnown = false;

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
  final TidalApiClient _apiClient = TidalApiClient();
  final DlnaManager _dlnaManager = DlnaManager.instance;

  final ValueNotifier<MediaTrack?> currentTrackNotifier = ValueNotifier(null);
  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier(false);
  final ValueNotifier<int> progressSecondsNotifier = ValueNotifier(0);
  final ValueNotifier<int> durationSecondsNotifier = ValueNotifier(210);
  final ValueNotifier<String> qualityBadgeNotifier = ValueNotifier('FLAC 16-bit');
  final ValueNotifier<bool> isShuffleNotifier = ValueNotifier(false);
  final ValueNotifier<PlaybackRepeatMode> repeatModeNotifier = ValueNotifier(PlaybackRepeatMode.off);

  /// 실시간 재생 대기열 (Queue List) Notifiers
  final ValueNotifier<List<MediaTrack>> queueNotifier = ValueNotifier([]);
  final ValueNotifier<int> queueIndexNotifier = ValueNotifier(-1);

  /// 통합 볼륨 (0~100)
  final ValueNotifier<int> volumeNotifier = ValueNotifier(50);

  Timer? _progressTimer;
  int _syncCounter = 0;

  /// 현재 재생 큐 및 원본(셔플 해제용) 큐
  List<MediaTrack> _queue = [];
  List<MediaTrack> _originalQueue = [];
  int _queueIndex = -1;

  MediaTrack? get currentTrack => currentTrackNotifier.value;
  bool get isPlaying => isPlayingNotifier.value;
  int get progressSeconds => progressSecondsNotifier.value;
  int get durationSeconds => durationSecondsNotifier.value;
  bool get isShuffle => isShuffleNotifier.value;
  PlaybackRepeatMode get repeatMode => repeatModeNotifier.value;
  List<MediaTrack> get queue => _queue;
  int get queueIndex => _queueIndex;

  /// 큐(플레이리스트/앨범 트랙 목록)를 명시적으로 설정합니다.
  void setQueue(List<MediaTrack> tracks, {int startIndex = 0}) {
    _originalQueue = List.of(tracks);
    if (isShuffleNotifier.value) {
      _applyShuffleQueue(startIndex);
    } else {
      _queue = List.of(tracks);
      _queueIndex = startIndex.clamp(0, tracks.isEmpty ? 0 : tracks.length - 1);
    }
    _notifyQueue();
  }

  void _notifyQueue() {
    queueNotifier.value = List.unmodifiable(_queue);
    queueIndexNotifier.value = _queueIndex;
  }

  /// 셔플 모드 토글
  void toggleShuffle() {
    isShuffleNotifier.value = !isShuffleNotifier.value;
    final current = currentTrack;
    if (isShuffleNotifier.value) {
      if (_originalQueue.isEmpty && _queue.isNotEmpty) {
        _originalQueue = List.of(_queue);
      }
      _applyShuffleQueue(_queueIndex);
      AppLogger.log('PLAYER', '🔀 셔플 모드 활성화 (큐 ${_queue.length}곡 셔플)', type: LogType.info);
    } else {
      // 셔플 해제: 원본 순서로 복원
      _queue = List.of(_originalQueue);
      if (current != null) {
        final idx = _queue.indexWhere((t) => t.id == current.id);
        _queueIndex = idx != -1 ? idx : 0;
      }
      AppLogger.log('PLAYER', '➡️ 셔플 모드 해제 (원본 순서 복원)', type: LogType.info);
    }
    _notifyQueue();
  }

  void _applyShuffleQueue(int currentIdx) {
    if (_originalQueue.isEmpty) return;
    final current = (currentIdx >= 0 && currentIdx < _originalQueue.length)
        ? _originalQueue[currentIdx]
        : currentTrack;

    final remaining = _originalQueue.where((t) => current == null || t.id != current.id).toList();
    remaining.shuffle(Random());

    _queue = current != null ? [current, ...remaining] : remaining;
    _queueIndex = 0;
    _notifyQueue();
  }

  /// 반복 모드 토글: off -> all -> one -> off
  void toggleRepeat() {
    switch (repeatModeNotifier.value) {
      case PlaybackRepeatMode.off:
        repeatModeNotifier.value = PlaybackRepeatMode.all;
        AppLogger.log('PLAYER', '🔁 전체 반복(All) 활성화', type: LogType.info);
        break;
      case PlaybackRepeatMode.all:
        repeatModeNotifier.value = PlaybackRepeatMode.one;
        AppLogger.log('PLAYER', '🔂 한 곡 반복(One) 활성화', type: LogType.info);
        break;
      case PlaybackRepeatMode.one:
        repeatModeNotifier.value = PlaybackRepeatMode.off;
        AppLogger.log('PLAYER', '⏹ 반복 모드 해제', type: LogType.info);
        break;
    }
  }

  /// 대기열에서 특정 인덱스의 곡을 바로 재생
  void playQueueIndex(int index) {
    if (index >= 0 && index < _queue.length) {
      _queueIndex = index;
      _notifyQueue();
      playTrack(_queue[index], queue: _queue, index: index);
    }
  }

  /// 볼륨 설정 (스마트폰 또는 DLNA 스피커)
  int? _lastPhoneVolume;

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

  static const int remoteVolumeStep = 2;

  DateTime _lastRemoteVolumeSentAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _remoteVolumeInterval = Duration(milliseconds: 200);

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

  /// 곡 재생. 현재 선택된 출력 기기에 따라 TIDAL SDK(폰) 또는 DLNA로 라우팅.
  Future<bool> playTrack(MediaTrack track, {List<MediaTrack>? queue, int? index}) async {
    _stopProgressTimer();

    currentTrackNotifier.value = track;
    isPlayingNotifier.value = true;
    progressSecondsNotifier.value = 0;
    
    // 정확한 곡 재생 시간 설정
    if (track.durationSeconds > 0) {
      durationSecondsNotifier.value = track.durationSeconds;
    }

    // 음원 품질 배지 동적 매핑
    _updateQualityBadge(track.audioQuality);

    AppLogger.log('PLAYER', '음원 재생 요청: "${track.title}" - ${track.artistName} (Track ID: ${track.id}, Duration: ${track.durationSeconds}s, Quality: ${track.audioQuality})', type: LogType.success);

    // 큐 관리: 명시적 큐가 주어지면 적용
    if (queue != null) {
      setQueue(queue, startIndex: index ?? 0);
    } else {
      // 큐가 없거나 현재 트랙이 기존 큐에 포함되지 않은 경우 -> 새 트랙 기준으로 초기화 및 similarTracks 자동 로드
      final idx = _queue.indexWhere((t) => t.id == track.id);
      if (idx != -1) {
        _queueIndex = idx;
        _notifyQueue();
      } else {
        _queue = [track];
        _originalQueue = [track];
        _queueIndex = 0;
        _notifyQueue();
        // TIDAL similarTracks 자동 추천 큐 구성 (비동기)
        _autoFetchSimilarTracks(track.id);
      }
    }

    final selectedDevice = _dlnaManager.selectedDevice;

    if (!selectedDevice.isLocalSpeaker) {
      await _playViaDlna(track);
    } else {
      await _playViaPhone(track);
    }

    // 백그라운드 재생 유지를 위한 Foreground Service 활성화 (알림바 + WakeLock/WifiLock)
    TidalSdkNativeBridge.startForegroundService(title: track.title, artist: track.artistName);

    _startProgressTimer();
    return true;
  }

  void _updateQualityBadge(String? quality) {
    final q = (quality ?? '').toUpperCase();
    if (q.contains('HI_RES') || q.contains('HIRES') || q.contains('MAX') || q.contains('MQA')) {
      qualityBadgeNotifier.value = 'MAX 24-bit / 192kHz';
    } else if (q.contains('LOSSLESS') || q.contains('FLAC')) {
      qualityBadgeNotifier.value = 'FLAC 16-bit / 44.1kHz';
    } else if (q.contains('HIGH')) {
      qualityBadgeNotifier.value = 'AAC 320kbps';
    } else if (q.contains('LOW')) {
      qualityBadgeNotifier.value = 'AAC 96kbps';
    } else {
      qualityBadgeNotifier.value = 'Lossless FLAC';
    }
  }

  /// 트랙 단독 재생 시 TIDAL 연관 추천곡(similarTracks)을 백그라운드로 가져와 큐를 채웁니다.
  Future<void> _autoFetchSimilarTracks(String trackId) async {
    try {
      final token = await _authRepo.autoLogin();
      if (token == null) return;
      final similars = await _apiClient.getSimilarTracks(trackId, token.accessToken, limit: 30);
      if (similars.isNotEmpty && currentTrack?.id == trackId) {
        final newTracks = similars.where((t) => t.id != trackId).toList();
        _queue = [currentTrack!, ...newTracks];
        _originalQueue = List.of(_queue);
        _notifyQueue();
        AppLogger.log('PLAYER', '✨ 연관 추천곡 ${newTracks.length}개 자동 큐 등록 완료', type: LogType.success);
      }
    } catch (e) {
      AppLogger.log('PLAYER', '연관 추천곡 조회 실패: $e', type: LogType.warning);
    }
  }

  /// 폰 내장 스피커 재생 (TIDAL 공식 SDK playbackEngine)
  Future<void> _playViaPhone(MediaTrack track) async {
    await _authRepo.autoLogin();
    AppLogger.log('PLAYER', '📱 스마트폰 TIDAL SDK 재생 요청 (Track ID: ${track.id})', type: LogType.network);
    await TidalSdkNativeBridge.playTrack(trackId: track.id);
  }

  /// DLNA 스피커 재생
  Future<void> _playViaDlna(MediaTrack track) async {
    // 폰 내장 스피커 오디오 출력을 완전 정지 (동시 재생 방지)
    await TidalSdkNativeBridge.stopTrack();
    AppLogger.log('PLAYER', '⏹ 스마트폰 TIDAL SDK 완전 정지 (DLNA 단독 재생)', type: LogType.info);

    String proxyUrl = '';
    try {
      final token = await _authRepo.autoLogin();
      if (token != null) {
        final playbackInfo = await _apiClient.getPlaybackInfo(track.id, token.accessToken);
        if (playbackInfo != null) {
          if (playbackInfo.audioQuality.isNotEmpty) {
            _updateQualityBadge(playbackInfo.audioQuality);
          }
          proxyUrl = await TidalSdkNativeBridge.registerTrackStream(
            trackId: track.id,
            directUrl: playbackInfo.streamUrl,
            manifestXml: playbackInfo.manifest,
            allowedHost: Uri.tryParse(_dlnaManager.selectedDevice.locationUrl)?.host ?? '',
          );
          AppLogger.log('PLAYER', 'DLNA 프록시 주소 준비 완료 (Quality: ${playbackInfo.audioQuality})', type: LogType.success);
        }
      }
    } catch (e) {
      AppLogger.log('PLAYER', 'TIDAL 재생 정보 조회 예외: $e', type: LogType.error);
    }

    if (proxyUrl.isEmpty) {
      AppLogger.log('PLAYER', 'DLNA 프록시 스트림 URL 생성 실패 - DLNA 재생 불가', type: LogType.error);
      isPlayingNotifier.value = false;
      return;
    }

    AppLogger.log('PLAYER', '🔊 DLNA 재생: "${_dlnaManager.selectedDevice.friendlyName}"', type: LogType.network);

    final ok = await _dlnaManager.playOnSelectedDevice(streamUrl: proxyUrl, title: track.title);
    if (!ok) {
      AppLogger.log('PLAYER', 'DLNA 재생 명령 실패', type: LogType.error);
      isPlayingNotifier.value = false;
    }
  }

  /// 출력 기기 전환
  Future<void> switchPlaybackDevice(DlnaDevice newDevice) async {
    final currentDevice = _dlnaManager.selectedDevice;
    final track = currentTrackNotifier.value;

    if (currentDevice.udn == newDevice.udn) return;

    AppLogger.log('PLAYER', '출력 기기 전환: "${currentDevice.friendlyName}" → "${newDevice.friendlyName}"', type: LogType.info);

    if (isPlayingNotifier.value && track != null) {
      if (!currentDevice.isLocalSpeaker) {
        await _dlnaManager.stopCurrent();
        AppLogger.log('PLAYER', '기존 DLNA 재생 정지 완료', type: LogType.info);
      }

      _dlnaManager.selectDevice(newDevice);
      await playTrack(track);
    } else {
      _dlnaManager.selectDevice(newDevice);
    }
  }

  void _startProgressTimer() {
    _stopProgressTimer();
    _syncCounter = 0;
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!isPlayingNotifier.value) return;
      final current = progressSecondsNotifier.value;
      final max = durationSecondsNotifier.value;

      // 4초마다 DLNA 스피커의 실제 재생 위치와 Duration을 동기화하여 오차 보정
      if (!_dlnaManager.selectedDevice.isLocalSpeaker) {
        _syncCounter++;
        if (_syncCounter % 4 == 0) {
          final pos = await _dlnaManager.syncPosition();
          if (pos != null) {
            final speakerProgress = pos['progress'] ?? 0;
            final speakerDuration = pos['duration'] ?? 0;
            if (speakerProgress > 0 && (speakerProgress - progressSecondsNotifier.value).abs() > 2) {
              progressSecondsNotifier.value = speakerProgress;
            }
            if (speakerDuration > 0 && durationSecondsNotifier.value != speakerDuration) {
              durationSecondsNotifier.value = speakerDuration;
            }
          }
        }
      }

      if (current < max) {
        progressSecondsNotifier.value = current + 1;
      } else {
        // 곡 종료 시: 한 곡 반복 / 다음 곡 자동 재생
        _stopProgressTimer();
        AppLogger.log('PLAYER', '🎵 곡 재생 완료 -> 다음 곡 자동 재생 시도', type: LogType.info);
        skipToNext(autoPlay: true);
      }
    });
  }

  void _stopProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  void togglePlayPause() {
    if (currentTrackNotifier.value == null) return;
    if (isPlayingNotifier.value) {
      pause();
    } else {
      resume();
    }
  }

  void pause() {
    isPlayingNotifier.value = false;
    _stopProgressTimer();
    if (_dlnaManager.selectedDevice.isLocalSpeaker) {
      TidalSdkNativeBridge.pauseTrack();
    } else {
      _dlnaManager.pauseCurrent();
    }
    AppLogger.log('PLAYER', '음원 일시정지', type: LogType.info);
  }

  void resume() {
    if (currentTrackNotifier.value == null) return;
    isPlayingNotifier.value = true;
    _startProgressTimer();
    if (_dlnaManager.selectedDevice.isLocalSpeaker) {
      TidalSdkNativeBridge.resumeTrack();
    } else {
      _dlnaManager.resumeCurrent();
    }
    AppLogger.log('PLAYER', '음원 재생 재개: ${currentTrackNotifier.value!.title}', type: LogType.info);
  }

  /// 재생 위치 탐색(Seek)
  void seekTo(int seconds) {
    final clamped = seconds.clamp(0, durationSecondsNotifier.value);
    progressSecondsNotifier.value = clamped;
    if (_dlnaManager.selectedDevice.isLocalSpeaker) {
      TidalSdkNativeBridge.seekTrack(clamped * 1000);
    } else {
      _dlnaManager.seek(clamped);
    }
  }

  void stop() {
    _stopProgressTimer();
    isPlayingNotifier.value = false;
    progressSecondsNotifier.value = 0;
    TidalSdkNativeBridge.stopForegroundService();
    if (_dlnaManager.selectedDevice.isLocalSpeaker) {
      TidalSdkNativeBridge.stopTrack();
    } else {
      _dlnaManager.stopCurrent();
    }
  }

  /// 다음 곡으로 이동
  void skipToNext({bool autoPlay = false}) {
    if (repeatModeNotifier.value == PlaybackRepeatMode.one && autoPlay && currentTrack != null) {
      // 한 곡 반복 모드이고 곡이 끝나서 넘어온 경우: 같은 곡 처음부터 재개
      seekTo(0);
      playTrack(currentTrack!);
      return;
    }

    if (_queue.isNotEmpty && _queueIndex < _queue.length - 1) {
      _queueIndex++;
      _notifyQueue();
      playTrack(_queue[_queueIndex]);
      AppLogger.log('PLAYER', '다음 곡: "${_queue[_queueIndex].title}" (큐 인덱스: $_queueIndex / ${_queue.length})', type: LogType.info);
    } else if (_queue.isNotEmpty && repeatModeNotifier.value == PlaybackRepeatMode.all) {
      // 전체 반복 모드: 첫 곡으로 순환
      _queueIndex = 0;
      _notifyQueue();
      playTrack(_queue[0]);
      AppLogger.log('PLAYER', '🔁 전체 반복: 첫 곡으로 순환 ("${_queue[0].title}")', type: LogType.info);
    } else {
      // 큐가 끝나면 추가 추천곡 가져오기 시도
      if (currentTrack != null) {
        _autoFetchSimilarTracks(currentTrack!.id);
      }
      if (_dlnaManager.selectedDevice.isLocalSpeaker) {
        TidalSdkNativeBridge.skipToNext();
      }
    }
  }

  /// 이전 곡으로 이동
  void skipToPrevious() {
    if (progressSecondsNotifier.value > 3) {
      seekTo(0);
      return;
    }

    if (_queue.isNotEmpty && _queueIndex > 0) {
      _queueIndex--;
      _notifyQueue();
      playTrack(_queue[_queueIndex]);
      AppLogger.log('PLAYER', '이전 곡: "${_queue[_queueIndex].title}" (큐 인덱스: $_queueIndex)', type: LogType.info);
    } else {
      seekTo(0);
      AppLogger.log('PLAYER', '이전 곡 없음 → 현재 곡 처음으로', type: LogType.info);
    }
  }
}
