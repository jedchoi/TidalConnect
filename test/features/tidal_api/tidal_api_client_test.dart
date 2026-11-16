import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tidal_connect_lite/features/tidal_api/data/tidal_api_client.dart';
import 'package:tidal_connect_lite/features/tidal_api/domain/models/media_item.dart';

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
        'manifest': b64(jsonEncode({'mimeType': 'audio/flac', 'codecs': 'flac', 'urls': ['https://cdn.example/a.flac?sig=1']})),
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
}
