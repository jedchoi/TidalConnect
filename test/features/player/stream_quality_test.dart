import 'package:flutter_test/flutter_test.dart';
import 'package:tidal_connect_lite/features/player/data/backends/playback_backend.dart';
import 'package:tidal_connect_lite/features/tidal_api/domain/models/media_item.dart';

void main() {
  test('실제 비트 깊이·샘플레이트로 배지를 만든다', () {
    const q = StreamQuality(audioQuality: 'HI_RES_LOSSLESS', bitDepth: 24, sampleRate: 96000);
    expect(q.label, 'Hi-Res FLAC · 24-bit / 96kHz');
    expect(q.isHiRes, isTrue);
  });

  test('44.1kHz는 소수점 한 자리로 쓴다', () {
    const q = StreamQuality(audioQuality: 'LOSSLESS', bitDepth: 16, sampleRate: 44100);
    expect(q.label, 'FLAC · 16-bit / 44.1kHz');
    expect(q.isHiRes, isFalse);
  });

  test('세부 정보가 없으면 음질 이름만, 미리 듣기는 표시를 붙인다', () {
    expect(const StreamQuality(audioQuality: 'HIGH').label, 'AAC 320kbps');
    expect(const StreamQuality(audioQuality: 'LOSSLESS', preview: true).label, 'FLAC · 미리 듣기');
    expect(const StreamQuality(audioQuality: '').label, '');
  });

  test('앨범 음질은 mediaMetadata 태그를 우선한다', () {
    final album = MediaAlbum.fromJson({
      'id': 1,
      'title': 'A',
      'audioQuality': 'LOSSLESS',
      'mediaMetadata': {
        'tags': ['LOSSLESS', 'HIRES_LOSSLESS'],
      },
    });
    expect(album.audioQuality, 'HI_RES_LOSSLESS');
    expect(album.qualityLabel, 'Hi-Res FLAC');
  });

  test('음질 정보가 없는 앨범은 배지를 보여주지 않는다', () {
    expect(MediaAlbum.fromJson({'id': 1, 'title': 'A'}).qualityLabel, '');
  });
}
