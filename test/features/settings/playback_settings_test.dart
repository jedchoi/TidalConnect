import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tidal_connect_lite/features/settings/data/playback_settings.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('저장된 값이 없으면 무손실', () async {
    final settings = PlaybackSettings();
    await settings.load();
    expect(settings.audioQuality.value, AudioQualityOption.lossless);
  });

  test('바꾼 음질을 저장하고 다음 실행에서 불러온다', () async {
    await PlaybackSettings().setAudioQuality(AudioQualityOption.hiRes);

    final reloaded = PlaybackSettings();
    await reloaded.load();
    expect(reloaded.audioQuality.value, AudioQualityOption.hiRes);
    expect(reloaded.audioQuality.value.apiValue, 'HI_RES_LOSSLESS');
  });

  test('알 수 없는 저장 값은 무손실로 되돌린다', () {
    expect(AudioQualityOption.fromApiValue('MQA'), AudioQualityOption.lossless);
  });
}
