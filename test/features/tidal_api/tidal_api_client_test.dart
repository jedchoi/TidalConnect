import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tidal_connect_lite/features/tidal_api/data/tidal_api_client.dart';
import 'package:tidal_connect_lite/features/tidal_api/domain/models/media_item.dart';

import '../../helpers/fakes.dart';

void main() {
  test('MediaTrack should parse JSON payload correctly', () {
    final json = {
      'id': 12345,
      'title': 'Test Song',
      'artist': {'name': 'Test Artist'},
      'album': {'cover': 'cover-uuid-1234', 'title': 'Test Album'},
      'duration': 210,
    };

    final track = MediaTrack.fromJson(json);
    expect(track.id, '12345');
    expect(track.title, 'Test Song');
    expect(track.artistName, 'Test Artist');
    expect(track.albumTitle, 'Test Album');
    expect(track.coverUrl, contains('cover/uuid/1234'));
  });

  test('MediaAlbum should parse JSON payload correctly', () {
    final json = {
      'id': 999,
      'title': 'Album Title',
      'artist': {'name': 'Album Artist'},
      'cover': 'album-cover-uuid',
      'numberOfTracks': 10,
    };

    final album = MediaAlbum.fromJson(json);
    expect(album.id, '999');
    expect(album.title, 'Album Title');
    expect(album.numberOfTracks, 10);
    expect(album.coverUrl, contains('album/cover/uuid'));
  });

  test('MediaPlaylist should parse JSON payload correctly', () {
    final json = {
      'uuid': 'playlist-uuid-123',
      'title': 'My Playlist',
      'description': 'Playlist Description',
      'squareImage': 'square-img-uuid',
      'numberOfTracks': 25,
    };

    final playlist = MediaPlaylist.fromJson(json);
    expect(playlist.id, 'playlist-uuid-123');
    expect(playlist.title, 'My Playlist');
    expect(playlist.numberOfTracks, 25);
    expect(playlist.coverUrl, contains('square/img/uuid'));
  });

  test('MediaArtist should parse JSON payload correctly', () {
    final json = {
      'id': 888,
      'name': 'Artist Name',
      'picture': 'artist-pic-uuid',
    };

    final artist = MediaArtist.fromJson(json);
    expect(artist.id, '888');
    expect(artist.name, 'Artist Name');
    expect(artist.pictureUrl, contains('artist/pic/uuid'));
  });

  group('parsePlaybackInfo', () {
    String b64(String s) => base64.encode(utf8.encode(s));

    test('BTS manifest yields a single direct URL and its MIME type', () {
      final info = TidalApiClient.parsePlaybackInfo({
        'audioQuality': 'LOSSLESS',
        'manifestMimeType': 'application/vnd.tidal.bts',
        'manifest': b64(jsonEncode({
          'mimeType': 'audio/flac',
          'codecs': 'flac',
          'urls': ['https://cdn.example/a.flac?sig=1']
        })),
      }, fallbackQuality: 'LOSSLESS')!;
      expect(info.isDash, isFalse);
      expect(info.streamUrl, 'https://cdn.example/a.flac?sig=1');
      expect(info.mimeType, 'audio/flac');
    });

    test('DASH manifest keeps the MPD text', () {
      final info = TidalApiClient.parsePlaybackInfo({
        'audioQuality': 'HI_RES_LOSSLESS',
        'manifestMimeType': 'application/dash+xml',
        'manifest': b64('<?xml version="1.0"?><MPD></MPD>'),
      }, fallbackQuality: 'HI_RES_LOSSLESS')!;
      expect(info.isDash, isTrue);
      expect(info.manifest, contains('<MPD>'));
    });

    test('lowerAudioQuality steps down one level', () {
      expect(lowerAudioQuality('HI_RES_LOSSLESS'), 'LOSSLESS');
      expect(lowerAudioQuality('LOW'), isNull);
    });
  });

  group('페이지네이션', () {
    Map<String, dynamic> trackJson(int id) => {
          'id': id,
          'title': 'T$id',
          'duration': 100,
          'artist': {'name': 'A'},
          'album': {'title': 'Al', 'cover': ''},
        };

    TidalApiClient client(Map<String, dynamic> Function(RequestOptions o) respond, List<RequestOptions> seen) {
      final dio = Dio(BaseOptions(baseUrl: TidalApiClient.baseUrl))
        ..httpClientAdapter = FakeAdapter((o) async {
          seen.add(o);
          return jsonBody(respond(o));
        });
      return TidalApiClient(dio: dio);
    }

    test('offset·limit을 보내고 totalNumberOfItems로 다음 페이지 여부를 정한다', () async {
      final seen = <RequestOptions>[];
      final api = client(
        (o) => {
          'limit': 2,
          'offset': o.queryParameters['offset'],
          'totalNumberOfItems': 3,
          'items': [
            for (var i = o.queryParameters['offset'] as int; i < 3 && i < (o.queryParameters['offset'] as int) + 2; i++)
              {'item': trackJson(i)},
          ],
        },
        seen,
      );

      final first = await api.getFavoriteTracks(userId: 'u', limit: 2);
      expect(first.items.map((t) => t.id), ['0', '1']);
      expect(first.total, 3);
      expect(first.hasMore, isTrue);

      final second = await api.getFavoriteTracks(userId: 'u', offset: 2, limit: 2);
      expect(second.items.map((t) => t.id), ['2']);
      expect(second.hasMore, isFalse);

      expect(seen.first.queryParameters['offset'], 0);
      expect(seen.last.queryParameters['offset'], 2);
      expect(seen.first.queryParameters['countryCode'], 'US');
    });

    test('전체 개수가 없으면 꽉 찬 페이지일 때만 다음이 있다고 본다', () async {
      final api = client(
          (o) => {
                'items': [for (var i = 0; i < 2; i++) trackJson(i)]
              },
          []);
      expect((await api.getAlbumTracks('a', limit: 2)).hasMore, isTrue);
      expect((await api.getAlbumTracks('a', limit: 3)).hasMore, isFalse);
    });
  });

  test('searchAll은 한 번의 요청으로 네 종류 결과를 나눈다', () async {
    final seen = <RequestOptions>[];
    final dio = Dio(BaseOptions(baseUrl: TidalApiClient.baseUrl))
      ..httpClientAdapter = FakeAdapter((o) async {
        seen.add(o);
        return jsonBody({
          'tracks': {
            'items': [
              {
                'id': 1,
                'title': 'Song',
                'duration': 10,
                'artist': {'name': 'A'},
                'album': {'title': 'B'}
              },
            ],
          },
          'albums': {
            'items': [
              {
                'id': 2,
                'title': 'Album',
                'artist': {'name': 'A'},
                'cover': ''
              },
            ],
          },
          'artists': {
            'items': [
              {'id': 3, 'name': 'Artist', 'picture': null},
            ],
          },
          'playlists': {'items': []},
        });
      });
    final results = await TidalApiClient(dio: dio).searchAll('q');

    expect(seen.single.path, '/search');
    expect(seen.single.queryParameters['types'], 'TRACKS,ALBUMS,ARTISTS,PLAYLISTS');
    expect(results.tracks.single.title, 'Song');
    expect(results.albums.single.title, 'Album');
    expect(results.artists.single.name, 'Artist');
    expect(results.playlists, isEmpty);
    expect(results.isEmpty, isFalse);
  });

  test('즐겨찾기 추가는 폼으로 POST, 삭제는 경로에 ID를 붙여 DELETE', () async {
    final seen = <RequestOptions>[];
    final dio = Dio(BaseOptions(baseUrl: TidalApiClient.baseUrl))
      ..httpClientAdapter = FakeAdapter((o) async {
        seen.add(o);
        if (o.path.endsWith('/favorites/ids')) {
          return jsonBody({
            'TRACK': ['1', 2],
            'PLAYLIST': ['uuid-1'],
          });
        }
        return jsonBody({});
      });
    final api = TidalApiClient(dio: dio);

    await api.addFavorite(userId: 'u', type: FavoriteType.playlist, id: 'uuid-1');
    expect(seen.last.method, 'POST');
    expect(seen.last.path, '/users/u/favorites/playlists');
    expect(seen.last.data, {'uuids': 'uuid-1'});

    await api.removeFavorite(userId: 'u', type: FavoriteType.track, id: '9');
    expect(seen.last.method, 'DELETE');
    expect(seen.last.path, '/users/u/favorites/tracks/9');

    final ids = await api.getFavoriteIds(userId: 'u');
    expect(ids[FavoriteType.track], {'1', '2'});
    expect(ids[FavoriteType.playlist], {'uuid-1'});
    expect(ids[FavoriteType.album], isEmpty);
  });
}
