import 'package:dio/dio.dart';
import '../../../core/utils/app_logger.dart';
import '../domain/models/media_item.dart';

class TidalApiClient {
  final Dio _dio;
  static const String baseUrl = 'https://api.tidal.com/v1';

  TidalApiClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 5),
              ),
            );

  Future<List<MediaAlbum>> getFavoriteAlbums(String accessToken) async {
    const endpoint = '/users/me/favorites/albums';
    AppLogger.log('TIDAL_API', 'GET $baseUrl$endpoint', type: LogType.network);
    try {
      final response = await _dio.get(
        endpoint,
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final items = response.data['items'] as List? ?? [];
      AppLogger.log('TIDAL_API', '내 즐겨찾기 앨범 수신 성공 [HTTP ${response.statusCode}]: ${items.length}개 항목', type: LogType.success);
      return items.map((e) => MediaAlbum.fromJson(e['item'] ?? e)).toList();
    } catch (e) {
      if (e is DioException) {
        AppLogger.log('TIDAL_API', '내 즐겨찾기 앨범 수신 오류 [HTTP ${e.response?.statusCode}]: ${e.response?.data ?? e.message}', type: LogType.error);
      }
      return [];
    }
  }

  Future<List<MediaPlaylist>> getFavoritePlaylists(String accessToken) async {
    const endpoint = '/users/me/favorites/playlists';
    AppLogger.log('TIDAL_API', 'GET $baseUrl$endpoint', type: LogType.network);
    try {
      final response = await _dio.get(
        endpoint,
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final items = response.data['items'] as List? ?? [];
      AppLogger.log('TIDAL_API', '내 즐겨찾기 플레이리스트 수신 성공 [HTTP ${response.statusCode}]: ${items.length}개 항목', type: LogType.success);
      return items.map((e) => MediaPlaylist.fromJson(e['playlist'] ?? e)).toList();
    } catch (e) {
      if (e is DioException) {
        AppLogger.log('TIDAL_API', '내 즐겨찾기 플레이리스트 수신 오류 [HTTP ${e.response?.statusCode}]: ${e.response?.data ?? e.message}', type: LogType.error);
      }
      return [];
    }
  }

  Future<List<MediaTrack>> getFavoriteTracks(String accessToken) async {
    const endpoint = '/users/me/favorites/tracks';
    AppLogger.log('TIDAL_API', 'GET $baseUrl$endpoint', type: LogType.network);
    try {
      final response = await _dio.get(
        endpoint,
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final items = response.data['items'] as List? ?? [];
      AppLogger.log('TIDAL_API', '내 즐겨찾기 트랙 수신 성공 [HTTP ${response.statusCode}]: ${items.length}개 항목', type: LogType.success);
      return items.map((e) => MediaTrack.fromJson(e['item'] ?? e)).toList();
    } catch (e) {
      if (e is DioException) {
        AppLogger.log('TIDAL_API', '내 즐겨찾기 트랙 수신 오류 [HTTP ${e.response?.statusCode}]: ${e.response?.data ?? e.message}', type: LogType.error);
      }
      return [];
    }
  }

  Future<List<MediaArtist>> getFavoriteArtists(String accessToken) async {
    const endpoint = '/users/me/favorites/artists';
    AppLogger.log('TIDAL_API', 'GET $baseUrl$endpoint', type: LogType.network);
    try {
      final response = await _dio.get(
        endpoint,
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final items = response.data['items'] as List? ?? [];
      AppLogger.log('TIDAL_API', '내 즐겨찾기 아티스트 수신 성공 [HTTP ${response.statusCode}]: ${items.length}개 항목', type: LogType.success);
      return items.map((e) => MediaArtist.fromJson(e['item'] ?? e)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<MediaTrack>> searchTracks(String query, String accessToken, {int limit = 20}) async {
    if (query.trim().isEmpty) return [];
    final endpoint = '/search/tracks?query=$query';
    AppLogger.log('TIDAL_API', 'GET $baseUrl/search/tracks (query=$query)', type: LogType.network);
    try {
      final response = await _dio.get(
        '/search/tracks',
        queryParameters: {'query': query, 'limit': limit, 'countryCode': 'US'},
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final items = response.data['items'] as List? ?? [];
      AppLogger.log('TIDAL_API', '트랙 검색 성공 [HTTP ${response.statusCode}]: ${items.length}개 수신', type: LogType.success);
      return items.map((e) => MediaTrack.fromJson(e)).toList();
    } catch (e) {
      if (e is DioException) {
        AppLogger.log('TIDAL_API', '트랙 검색 오류 [HTTP ${e.response?.statusCode}]: ${e.response?.data ?? e.message}', type: LogType.error);
      }
      return [];
    }
  }

  Future<List<MediaAlbum>> searchAlbums(String query, String accessToken, {int limit = 20}) async {
    if (query.trim().isEmpty) return [];
    AppLogger.log('TIDAL_API', 'GET $baseUrl/search/albums (query=$query)', type: LogType.network);
    try {
      final response = await _dio.get(
        '/search/albums',
        queryParameters: {'query': query, 'limit': limit, 'countryCode': 'US'},
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final items = response.data['items'] as List? ?? [];
      AppLogger.log('TIDAL_API', '앨범 검색 성공 [HTTP ${response.statusCode}]: ${items.length}개 수신', type: LogType.success);
      return items.map((e) => MediaAlbum.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<MediaPlaylist>> searchPlaylists(String query, String accessToken, {int limit = 20}) async {
    if (query.trim().isEmpty) return [];
    AppLogger.log('TIDAL_API', 'GET $baseUrl/search/playlists (query=$query)', type: LogType.network);
    try {
      final response = await _dio.get(
        '/search/playlists',
        queryParameters: {'query': query, 'limit': limit, 'countryCode': 'US'},
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final items = response.data['items'] as List? ?? [];
      AppLogger.log('TIDAL_API', '플레이리스트 검색 성공 [HTTP ${response.statusCode}]: ${items.length}개 수신', type: LogType.success);
      return items.map((e) => MediaPlaylist.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<String?> getStreamUrl(String trackId, String accessToken, {String soundQuality = 'LOSSLESS'}) async {
    const endpoint = '/tracks/urlpostpaystream';
    AppLogger.log('TIDAL_API', 'GET $baseUrl/tracks/$trackId/urlpostpaystream', type: LogType.network);
    try {
      final response = await _dio.get(
        '/tracks/$trackId/urlpostpaystream',
        queryParameters: {'soundQuality': soundQuality},
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final url = response.data['url'] as String?;
      AppLogger.log('TIDAL_API', '오디오 스트림 URL 발급 성공: $url', type: LogType.success);
      return url;
    } catch (e) {
      if (e is DioException) {
        AppLogger.log('TIDAL_API', '오디오 스트림 URL 발급 오류 [HTTP ${e.response?.statusCode}]: ${e.response?.data ?? e.message}', type: LogType.error);
      }
      return null;
    }
  }
}
