import 'package:flutter_test/flutter_test.dart';
import 'package:tidal_connect_lite/features/favorites/data/favorites_repository.dart';
import 'package:tidal_connect_lite/features/tidal_api/data/tidal_api_client.dart';

import '../../helpers/app_overrides.dart';

void main() {
  late FakeApiClient api;
  late FavoritesRepository repo;

  setUp(() {
    api = FakeApiClient();
    api.favoriteIds[FavoriteType.track]!.add('t1');
    repo = FavoritesRepository(api: api);
  });

  test('로그인 전에는 하트를 쓸 수 없다', () async {
    expect(repo.isAvailable, isFalse);
    expect(await repo.toggle(FavoriteType.track, 't1'), isFalse);
    expect(api.calls, isEmpty);
  });

  test('로그인하면 즐겨찾기 ID를 받아 표시한다', () async {
    await repo.setUser('u');
    expect(repo.isAvailable, isTrue);
    expect(repo.isFavorite(FavoriteType.track, 't1'), isTrue);
    expect(repo.isFavorite(FavoriteType.album, 't1'), isFalse);
  });

  test('누르면 추가·삭제 요청을 보내고 revision을 올린다', () async {
    await repo.setUser('u');
    expect(await repo.toggle(FavoriteType.album, 'a1'), isTrue);
    expect(repo.isFavorite(FavoriteType.album, 'a1'), isTrue);
    expect(await repo.toggle(FavoriteType.track, 't1'), isTrue);
    expect(repo.isFavorite(FavoriteType.track, 't1'), isFalse);
    expect(api.calls, containsAllInOrder(['addFavorite:album:a1', 'removeFavorite:track:t1']));
    expect(repo.revision, 2);
  });

  test('요청이 실패하면 되돌린다', () async {
    await repo.setUser('u');
    api.failFavoriteWrites = true;
    expect(await repo.toggle(FavoriteType.artist, 'r1'), isFalse);
    expect(repo.isFavorite(FavoriteType.artist, 'r1'), isFalse);
    expect(repo.revision, 0);
  });

  test('로그아웃하면 비운다', () async {
    await repo.setUser('u');
    await repo.setUser(null);
    expect(repo.isAvailable, isFalse);
    expect(repo.isFavorite(FavoriteType.track, 't1'), isFalse);
  });
}
