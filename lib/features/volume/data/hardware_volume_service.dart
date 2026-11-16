import 'dart:async';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';

/// 폰의 미디어 볼륨과 물리 볼륨 키를 다룬다.
class HardwareVolumeService {
  StreamSubscription<double>? _subscription;

  static int toVolumePercent(double doubleVolume) {
    return (doubleVolume.clamp(0.0, 1.0) * 100).round();
  }

  /// 폰 미디어 볼륨이 바뀔 때마다(볼륨 키 포함) 0~100 값으로 알린다.
  void listenPhysicalVolumeKeys(void Function(int volumePercent) onVolumeChanged) {
    try {
      _subscription?.cancel();
      _subscription = FlutterVolumeController.addListener((volume) {
        onVolumeChanged(toVolumePercent(volume));
      });
    } catch (_) {
      // 테스트 환경 등 플러그인이 없는 경우
    }
  }

  /// 볼륨 키를 누를 때 시스템 볼륨 UI를 보일지 정한다.
  /// 폰으로 재생할 때만 보이고, 스피커로 재생할 때는 폰 볼륨 막대가 혼동을 주므로 숨긴다.
  static void setShowSystemUI(bool show) {
    try {
      FlutterVolumeController.showSystemUI = show;
    } catch (_) {}
  }

  static Future<int?> getPhoneVolume() async {
    try {
      final volume = await FlutterVolumeController.getVolume();
      return volume == null ? null : toVolumePercent(volume);
    } catch (_) {
      return null;
    }
  }

  static Future<void> setPhoneVolume(int percent) async {
    try {
      await FlutterVolumeController.setVolume(percent.clamp(0, 100) / 100.0);
    } catch (_) {}
  }

  void dispose() {
    _subscription?.cancel();
    try {
      FlutterVolumeController.removeListener();
    } catch (_) {}
  }
}
