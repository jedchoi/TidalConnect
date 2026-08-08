import 'package:flutter_test/flutter_test.dart';
import 'package:tidal_connect_lite/features/volume/data/hardware_volume_service.dart';

void main() {
  test('Volume percentage conversion', () {
    expect(HardwareVolumeService.toVolumePercent(0.5), 50);
    expect(HardwareVolumeService.toVolumePercent(1.0), 100);
    expect(HardwareVolumeService.toVolumePercent(0.0), 0);
    expect(HardwareVolumeService.toVolumePercent(0.754), 75);
    expect(HardwareVolumeService.toVolumePercent(-0.1), 0);
    expect(HardwareVolumeService.toVolumePercent(1.5), 100);
  });
}
