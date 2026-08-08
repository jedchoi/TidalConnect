import 'dart:async';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';

class HardwareVolumeService {
  StreamSubscription<double>? _subscription;

  static int toVolumePercent(double doubleVolume) {
    return (doubleVolume.clamp(0.0, 1.0) * 100).round();
  }

  void listenPhysicalVolumeKeys(Function(int volumePercent) onVolumeChanged) {
    try {
      FlutterVolumeController.showSystemUI = false;
      _subscription?.cancel();
      _subscription = FlutterVolumeController.addListener((volume) {
        final percent = toVolumePercent(volume);
        onVolumeChanged(percent);
      });
    } catch (_) {
      // Fallback for non-supported test environments
    }
  }

  void dispose() {
    _subscription?.cancel();
    try {
      FlutterVolumeController.removeListener();
    } catch (_) {}
  }
}
