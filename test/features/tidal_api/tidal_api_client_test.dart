import 'package:flutter_test/flutter_test.dart';
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
}
