import 'package:dio/dio.dart';
import '../domain/models/media_item.dart';

class TidalApiClient {
  final Dio _dio;
  static const String baseUrl = 'https://api.tidal.com/v1';

  TidalApiClient({Dio? dio}) : _dio = dio ?? Dio(BaseOptions(baseUrl: baseUrl));

  Future<List<MediaAlbum>> getFavoriteAlbums(String accessToken) async {
    try {
      final response = await _dio.get(
        '/users/me/favorites/albums',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final items = response.data['items'] as List? ?? [];
      return items.map((e) => MediaAlbum.fromJson(e['item'] ?? e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<MediaPlaylist>> getFavoritePlaylists(String accessToken) async {
    try {
      final response = await _dio.get(
        '/users/me/favorites/playlists',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final items = response.data['items'] as List? ?? [];
      return items.map((e) => MediaPlaylist.fromJson(e['playlist'] ?? e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<MediaTrack>> getFavoriteTracks(String accessToken) async {
    try {
      final response = await _dio.get(
        '/users/me/favorites/tracks',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final items = response.data['items'] as List? ?? [];
      return items.map((e) => MediaTrack.fromJson(e['item'] ?? e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<MediaArtist>> getFavoriteArtists(String accessToken) async {
    try {
      final response = await _dio.get(
        '/users/me/favorites/artists',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final items = response.data['items'] as List? ?? [];
      return items.map((e) => MediaArtist.fromJson(e['item'] ?? e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<MediaTrack>> searchTracks(String query, String accessToken, {int limit = 20}) async {
    if (query.trim().isEmpty) return [];
    try {
      final response = await _dio.get(
        '/search/tracks',
        queryParameters: {'query': query, 'limit': limit, 'countryCode': 'US'},
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final items = response.data['items'] as List? ?? [];
      return items.map((e) => MediaTrack.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<MediaAlbum>> searchAlbums(String query, String accessToken, {int limit = 20}) async {
    if (query.trim().isEmpty) return [];
    try {
      final response = await _dio.get(
        '/search/albums',
        queryParameters: {'query': query, 'limit': limit, 'countryCode': 'US'},
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final items = response.data['items'] as List? ?? [];
      return items.map((e) => MediaAlbum.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<MediaPlaylist>> searchPlaylists(String query, String accessToken, {int limit = 20}) async {
    if (query.trim().isEmpty) return [];
    try {
      final response = await _dio.get(
        '/search/playlists',
        queryParameters: {'query': query, 'limit': limit, 'countryCode': 'US'},
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final items = response.data['items'] as List? ?? [];
      return items.map((e) => MediaPlaylist.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<String?> getStreamUrl(String trackId, String accessToken, {String soundQuality = 'LOSSLESS'}) async {
    try {
      final response = await _dio.get(
        '/tracks/$trackId/urlpostpaystream',
        queryParameters: {'soundQuality': soundQuality},
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      return response.data['url'] as String?;
    } catch (_) {
      return null;
    }
  }
}
