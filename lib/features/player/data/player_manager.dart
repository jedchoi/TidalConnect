import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/native/tidal_sdk_native_bridge.dart';
import '../../../core/utils/app_logger.dart';
import '../../auth/data/tidal_auth_repository.dart';
import '../../dlna/data/dlna_manager.dart';
import '../../tidal_api/data/tidal_api_client.dart';
import '../../tidal_api/domain/models/media_item.dart';

class PlayerManager {
  static final PlayerManager instance = PlayerManager._internal();
  PlayerManager._internal();

  final TidalAuthRepository _authRepo = TidalAuthRepository();
  final TidalApiClient _apiClient = TidalApiClient();
  final DlnaManager _dlnaManager = DlnaManager.instance;

  final ValueNotifier<MediaTrack?> currentTrackNotifier = ValueNotifier(null);
  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier(false);
  final ValueNotifier<int> progressSecondsNotifier = ValueNotifier(0);
  final ValueNotifier<int> durationSecondsNotifier = ValueNotifier(210);
  final ValueNotifier<String> qualityBadgeNotifier = ValueNotifier('Hi-Res Lossless FLAC');

  Timer? _progressTimer;

  MediaTrack? get currentTrack => currentTrackNotifier.value;
  bool get isPlaying => isPlayingNotifier.value;
  int get progressSeconds => progressSecondsNotifier.value;
  int get durationSeconds => durationSecondsNotifier.value;

  /// Plays a given track across native Tidal SDK / DLNA and updates global player UI state
  Future<bool> playTrack(MediaTrack track) async {
    _stopProgressTimer();

    currentTrackNotifier.value = track;
    isPlayingNotifier.value = true;
    progressSecondsNotifier.value = 0;
    durationSecondsNotifier.value = track.durationSeconds > 0 ? track.durationSeconds : 210;
    qualityBadgeNotifier.value = 'Hi-Res Lossless FLAC';

    AppLogger.log('PLAYER', '음원 재생 시작: "${track.title}" - ${track.artistName} (Track ID: ${track.id})', type: LogType.success);

    // 1. Fetch real stream URL from Tidal API
    String streamUrl = '';
    try {
      final token = await _authRepo.autoLogin();
      if (token != null) {
        final fetchedUrl = await _apiClient.getStreamUrl(track.id, token.accessToken);
        if (fetchedUrl != null && fetchedUrl.isNotEmpty) {
          streamUrl = fetchedUrl;
        }
      }
    } catch (_) {}

    // 2. Play on selected target (DLNA Remote Speaker vs. Smartphone Local Speaker)
    final selectedDevice = _dlnaManager.selectedDevice;
    if (!selectedDevice.isLocalSpeaker && streamUrl.isNotEmpty) {
      // Remote DLNA Speaker
      await _dlnaManager.playOnSelectedDevice(streamUrl: streamUrl, title: track.title);
    } else {
      // Local Phone Speaker via Android MediaPlayer / Native SDK Bridge
      await TidalSdkNativeBridge.playTrack(trackId: track.id, streamUrl: streamUrl);
    }

    // 3. Start real-time progress timer
    _startProgressTimer();

    return true;
  }

  void _startProgressTimer() {
    _stopProgressTimer();
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!isPlayingNotifier.value) return;

      final current = progressSecondsNotifier.value;
      final max = durationSecondsNotifier.value;

      if (current < max) {
        progressSecondsNotifier.value = current + 1;
      } else {
        // Track completed
        _stopProgressTimer();
        isPlayingNotifier.value = false;
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
    TidalSdkNativeBridge.pauseTrack();
    AppLogger.log('PLAYER', '음원 일시정지', type: LogType.info);
  }

  void resume() {
    if (currentTrackNotifier.value == null) return;
    isPlayingNotifier.value = true;
    _startProgressTimer();
    TidalSdkNativeBridge.resumeTrack();
    AppLogger.log('PLAYER', '음원 재생 재개: ${currentTrackNotifier.value!.title}', type: LogType.info);
  }

  void seekTo(int seconds) {
    progressSecondsNotifier.value = seconds.clamp(0, durationSecondsNotifier.value);
    TidalSdkNativeBridge.seekTrack(seconds * 1000);
  }

  void stop() {
    _stopProgressTimer();
    isPlayingNotifier.value = false;
    progressSecondsNotifier.value = 0;
    TidalSdkNativeBridge.stopTrack();
  }
}
