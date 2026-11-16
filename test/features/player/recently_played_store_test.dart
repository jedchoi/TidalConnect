import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tidal_connect_lite/features/player/data/recently_played_store.dart';
import 'package:tidal_connect_lite/features/tidal_api/domain/models/media_item.dart';

MediaTrack t(String id, {String quality = 'LOSSLESS'}) => MediaTrack(
      id: id,
      title: 'Track $id',
      artistName: 'Artist',
      albumTitle: 'Album',
      coverUrl: 'https://resources.tidal.com/images/a/b/640x640.jpg',
      durationSeconds: 100,
      audioQuality: quality,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('같은 곡은 맨 앞으로 옮기고 최대 개수를 지킨다', () async {
    final store = RecentlyPlayedStore();
    for (var i = 0; i < RecentlyPlayedStore.maxItems + 5; i++) {
      await store.add(t('$i'));
    }
    await store.add(t('10'));

    final ids = store.tracks.value.map((e) => e.id).toList();
    expect(ids.length, RecentlyPlayedStore.maxItems);
    expect(ids.first, '10');
    expect(ids.where((id) => id == '10').length, 1);
  });

  test('저장한 목록을 다음 실행에서 그대로 불러온다', () async {
    final store = RecentlyPlayedStore();
    await store.add(t('1', quality: 'HI_RES_LOSSLESS'));
    await store.add(t('2', quality: 'DOLBY_ATMOS'));

    final reloaded = RecentlyPlayedStore();
    await reloaded.load();
    final tracks = reloaded.tracks.value;
    expect(tracks.map((e) => e.id), ['2', '1']);
    expect(tracks[0].audioQuality, 'DOLBY_ATMOS');
    expect(tracks[1].audioQuality, 'HI_RES_LOSSLESS');
    expect(tracks[1].title, 'Track 1');
    expect(tracks[1].albumTitle, 'Album');
    expect(tracks[1].coverUrl, 'https://resources.tidal.com/images/a/b/640x640.jpg');
    expect(tracks[1].durationSeconds, 100);
  });

  test('지우면 저장소에서도 사라진다', () async {
    final store = RecentlyPlayedStore();
    await store.add(t('1'));
    await store.clear();
    final reloaded = RecentlyPlayedStore();
    await reloaded.load();
    expect(reloaded.tracks.value, isEmpty);
  });
}
