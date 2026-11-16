import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 스트리밍 음질 선택지.
enum AudioQualityOption {
  low('LOW', '보통', 'AAC 96kbps'),
  high('HIGH', '높음', 'AAC 320kbps'),
  lossless('LOSSLESS', '무손실', 'FLAC 16-bit / 44.1kHz'),
  hiRes('HI_RES_LOSSLESS', '최고(Hi-Res)', 'FLAC 최대 24-bit / 192kHz');

  const AudioQualityOption(this.apiValue, this.label, this.detail);

  /// TIDAL API·SDK에 넘기는 값.
  final String apiValue;
  final String label;
  final String detail;

  static AudioQualityOption fromApiValue(String? value) =>
      values.firstWhere((o) => o.apiValue == value, orElse: () => AudioQualityOption.lossless);
}

/// 기기에 저장하는 재생 설정.
class PlaybackSettings {
  static const String audioQualityKey = 'audio_quality';

  /// 현재 스트리밍 음질. 바꾸면 저장하고 구독자(PlayerManager)가 출력 기기에 적용한다.
  final ValueNotifier<AudioQualityOption> audioQuality = ValueNotifier(AudioQualityOption.lossless);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      audioQuality.value = AudioQualityOption.fromApiValue(prefs.getString(audioQualityKey));
    } catch (_) {}
  }

  Future<void> setAudioQuality(AudioQualityOption option) async {
    audioQuality.value = option;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(audioQualityKey, option.apiValue);
    } catch (_) {}
  }
}
