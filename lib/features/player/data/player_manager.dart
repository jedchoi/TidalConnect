import 'package:flutter/foundation.dart';
import '../../../core/native/tidal_sdk_native_bridge.dart';
import '../../../core/utils/app_logger.dart';
import '../../tidal_api/domain/models/media_item.dart';

class PlayerManager {
  static final PlayerManager instance = PlayerManager._internal();
  PlayerManager._internal();

  final ValueNotifier<MediaTrack?> currentTrackNotifier = ValueNotifier(null);
  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier(false);
  final ValueNotifier<int> progressSecondsNotifier = ValueNotifier(0);
  final ValueNotifier<int> durationSecondsNotifier = ValueNotifier(0);
  final ValueNotifier<String> qualityBadgeNotifier = ValueNotifier('Hi-Res Lossless FLAC');

  MediaTrack? get currentTrack => currentTrackNotifier.value;
  bool get isPlaying => isPlayingNotifier.value;

  /// Plays a given track across native Tidal SDK / DLNA and updates global player UI state
  Future<bool> playTrack(MediaTrack track) async {
    currentTrackNotifier.value = track;
    isPlayingNotifier.value = true;
    progressSecondsNotifier.value = 0;
    durationSecondsNotifier.value = track.durationSeconds > 0 ? track.durationSeconds : 210;
    qualityBadgeNotifier.value = 'Hi-Res Lossless FLAC';

    AppLogger.log('PLAYER', '음원 재생 시작: "${track.title}" - ${track.artistName} (Track ID: ${track.id})', type: LogType.success);

    final success = await TidalSdkNativeBridge.playTrack(trackId: track.id);
    return success;
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
    TidalSdkNativeBridge.stopTrack();
    AppLogger.log('PLAYER', '음원 일시정지', type: LogType.info);
  }

  void resume() {
    if (currentTrackNotifier.value == null) return;
    isPlayingNotifier.value = true;
    TidalSdkNativeBridge.playTrack(trackId: currentTrackNotifier.value!.id);
    AppLogger.log('PLAYER', '음원 재생 재개: ${currentTrackNotifier.value!.title}', type: LogType.info);
  }

  void seekTo(int seconds) {
    progressSecondsNotifier.value = seconds;
  }
}
