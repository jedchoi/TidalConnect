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
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 8),
              ),
            );

  Map<String, String> _buildHeaders(String accessToken) {
    return {
      'Authorization': 'Bearer $accessToken',
      'Accept': 'application/json',
    };
  }

  // ──────────────────────────────────────────────
  // 즐겨찾기 (My Collection) Endpoints (v1)
  // ──────────────────────────────────────────────

  Future<List<MediaAlbum>> getFavoriteAlbums(String accessToken, {String userId = 'me'}) async {
    final effectiveUserId = userId.isEmpty ? 'me' : userId;
    final endpoint = '/users/$effectiveUserId/favorites/albums';
    AppLogger.log('TIDAL_API', 'GET $baseUrl$endpoint (countryCode=US)', type: LogType.network);
    try {
      final response = await _dio.get(
        endpoint,
        queryParameters: {'countryCode': 'US', 'limit': 50},
        options: Options(headers: _buildHeaders(accessToken)),
      );
      final items = response.data['items'] as List? ?? [];
      AppLogger.log('TIDAL_API', '내 즐겨찾기 앨범 수신 성공 [HTTP ${response.statusCode}]: ${items.length}개', type: LogType.success);
      return items.map((e) => MediaAlbum.fromJson(e['item'] ?? e)).toList();
    } catch (e) {
      if (e is DioException && e.response != null) {
        AppLogger.log('TIDAL_API', '내 즐겨찾기 앨범 수신 오류 [HTTP ${e.response?.statusCode}]: ${e.response?.data}', type: LogType.error);
      } else {
        AppLogger.log('TIDAL_API', '내 즐겨찾기 앨범 수신 오류: $e', type: LogType.error);
      }
      return [];
    }
  }

  Future<List<MediaPlaylist>> getFavoritePlaylists(String accessToken, {String userId = 'me'}) async {
    final effectiveUserId = userId.isEmpty ? 'me' : userId;
    final endpoint = '/users/$effectiveUserId/favorites/playlists';
    AppLogger.log('TIDAL_API', 'GET $baseUrl$endpoint (countryCode=US)', type: LogType.network);
    try {
      final response = await _dio.get(
        endpoint,
        queryParameters: {'countryCode': 'US', 'limit': 50},
        options: Options(headers: _buildHeaders(accessToken)),
      );
      final items = response.data['items'] as List? ?? [];
      AppLogger.log('TIDAL_API', '내 즐겨찾기 플레이리스트 수신 성공 [HTTP ${response.statusCode}]: ${items.length}개', type: LogType.success);
      return items.map((e) => MediaPlaylist.fromJson(e['playlist'] ?? e)).toList();
    } catch (e) {
      if (e is DioException && e.response != null) {
        AppLogger.log('TIDAL_API', '내 즐겨찾기 플레이리스트 수신 오류 [HTTP ${e.response?.statusCode}]: ${e.response?.data}', type: LogType.error);
      } else {
        AppLogger.log('TIDAL_API', '내 즐겨찾기 플레이리스트 수신 오류: $e', type: LogType.error);
      }
      return [];
    }
  }

  Future<List<MediaTrack>> getFavoriteTracks(String accessToken, {String userId = 'me'}) async {
    final effectiveUserId = userId.isEmpty ? 'me' : userId;
    final endpoint = '/users/$effectiveUserId/favorites/tracks';
    AppLogger.log('TIDAL_API', 'GET $baseUrl$endpoint (countryCode=US)', type: LogType.network);
    try {
      final response = await _dio.get(
        endpoint,
        queryParameters: {'countryCode': 'US', 'limit': 50},
        options: Options(headers: _buildHeaders(accessToken)),
      );
      final items = response.data['items'] as List? ?? [];
      AppLogger.log('TIDAL_API', '내 즐겨찾기 트랙 수신 성공 [HTTP ${response.statusCode}]: ${items.length}개', type: LogType.success);
      return items.map((e) => MediaTrack.fromJson(e['item'] ?? e)).toList();
    } catch (e) {
      if (e is DioException && e.response != null) {
        AppLogger.log('TIDAL_API', '내 즐겨찾기 트랙 수신 오류 [HTTP ${e.response?.statusCode}]: ${e.response?.data}', type: LogType.error);
      } else {
        AppLogger.log('TIDAL_API', '내 즐겨찾기 트랙 수신 오류: $e', type: LogType.error);
      }
      return [];
    }
  }

  // ──────────────────────────────────────────────
  // 앨범 및 플레이리스트 내부 세부 트랙 조회
  // ──────────────────────────────────────────────

  /// 앨범 내 트랙 목록 조회
  Future<List<MediaTrack>> getAlbumTracks(String albumId, String accessToken) async {
    final endpoint = '/albums/$albumId/tracks';
    AppLogger.log('TIDAL_API', 'GET $baseUrl$endpoint (countryCode=US)', type: LogType.network);
    try {
      final response = await _dio.get(
        endpoint,
        queryParameters: {'countryCode': 'US', 'limit': 100},
        options: Options(headers: _buildHeaders(accessToken)),
      );
      final items = response.data['items'] as List? ?? [];
      AppLogger.log('TIDAL_API', '앨범 트랙 목록 수신 성공 [HTTP ${response.statusCode}]: ${items.length}개', type: LogType.success);
      return items.map((e) => MediaTrack.fromJson(e)).toList();
    } catch (e) {
      AppLogger.log('TIDAL_API', '앨범 트랙 수신 오류: $e', type: LogType.error);
      return [];
    }
  }

  /// 플레이리스트 내 트랙 목록 조회
  Future<List<MediaTrack>> getPlaylistTracks(String playlistId, String accessToken) async {
    final endpoint = '/playlists/$playlistId/tracks';
    AppLogger.log('TIDAL_API', 'GET $baseUrl$endpoint (countryCode=US)', type: LogType.network);
    try {
      final response = await _dio.get(
        endpoint,
        queryParameters: {'countryCode': 'US', 'limit': 100},
        options: Options(headers: _buildHeaders(accessToken)),
      );
      final items = response.data['items'] as List? ?? [];
      AppLogger.log('TIDAL_API', '플레이리스트 트랙 목록 수신 성공 [HTTP ${response.statusCode}]: ${items.length}개', type: LogType.success);
      return items.map((e) {
        if (e['item'] != null) {
          return MediaTrack.fromJson(e['item']);
        }
        return MediaTrack.fromJson(e);
      }).toList();
    } catch (e) {
      AppLogger.log('TIDAL_API', '플레이리스트 트랙 수신 오류: $e', type: LogType.error);
      return [];
    }
  }

  // ──────────────────────────────────────────────
  // 추천 / 피처드 (Explore / Recommendations) Endpoints
  // ──────────────────────────────────────────────

  Future<List<MediaAlbum>> getFeaturedAlbums(String accessToken) async {
    try {
      final response = await _dio.get(
        '/featured/new/albums',
        queryParameters: {'countryCode': 'US', 'limit': 20},
        options: Options(headers: _buildHeaders(accessToken)),
      );
      final items = response.data['items'] as List? ?? [];
      if (items.isNotEmpty) {
        return items.map((e) => MediaAlbum.fromJson(e)).toList();
      }
    } catch (_) {}

    // Fallback search for top master albums
    return searchAlbums('Master', accessToken, limit: 10);
  }

  Future<List<MediaPlaylist>> getFeaturedPlaylists(String accessToken) async {
    try {
      final response = await _dio.get(
        '/featured/recommended/playlists',
        queryParameters: {'countryCode': 'US', 'limit': 20},
        options: Options(headers: _buildHeaders(accessToken)),
      );
      final items = response.data['items'] as List? ?? [];
      if (items.isNotEmpty) {
        return items.map((e) => MediaPlaylist.fromJson(e)).toList();
      }
    } catch (_) {}

    // Fallback search for popular playlists
    return searchPlaylists('Tidal Master', accessToken, limit: 10);
  }

  Future<List<MediaTrack>> getFeaturedTracks(String accessToken) async {
    try {
      final response = await _dio.get(
        '/featured/recommended/tracks',
        queryParameters: {'countryCode': 'US', 'limit': 20},
        options: Options(headers: _buildHeaders(accessToken)),
      );
      final items = response.data['items'] as List? ?? [];
      if (items.isNotEmpty) {
        return items.map((e) => MediaTrack.fromJson(e)).toList();
      }
    } catch (_) {}

    // Fallback search for top tracks
    return searchTracks('Top Hits', accessToken, limit: 15);
  }

  // ──────────────────────────────────────────────
  // 검색 (Search) Endpoints
  // ──────────────────────────────────────────────

  Future<List<MediaTrack>> searchTracks(String query, String accessToken, {int limit = 20}) async {
    if (query.trim().isEmpty) return [];
    AppLogger.log('TIDAL_API', 'GET $baseUrl/search/tracks (query=$query, countryCode=US)', type: LogType.network);
    try {
      final response = await _dio.get(
        '/search/tracks',
        queryParameters: {'query': query, 'limit': limit, 'countryCode': 'US'},
        options: Options(headers: _buildHeaders(accessToken)),
      );
      final items = response.data['items'] as List? ?? [];
      AppLogger.log('TIDAL_API', '트랙 검색 성공 [HTTP ${response.statusCode}]: ${items.length}개 수신', type: LogType.success);
      return items.map((e) => MediaTrack.fromJson(e)).toList();
    } catch (e) {
      if (e is DioException && e.response != null) {
        AppLogger.log('TIDAL_API', '트랙 검색 오류 [HTTP ${e.response?.statusCode}]: ${e.response?.data}', type: LogType.error);
      } else {
        AppLogger.log('TIDAL_API', '트랙 검색 오류: $e', type: LogType.error);
      }
      return [];
    }
  }

  Future<List<MediaAlbum>> searchAlbums(String query, String accessToken, {int limit = 20}) async {
    if (query.trim().isEmpty) return [];
    AppLogger.log('TIDAL_API', 'GET $baseUrl/search/albums (query=$query, countryCode=US)', type: LogType.network);
    try {
      final response = await _dio.get(
        '/search/albums',
        queryParameters: {'query': query, 'limit': limit, 'countryCode': 'US'},
        options: Options(headers: _buildHeaders(accessToken)),
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
    AppLogger.log('TIDAL_API', 'GET $baseUrl/search/playlists (query=$query, countryCode=US)', type: LogType.network);
    try {
      final response = await _dio.get(
        '/search/playlists',
        queryParameters: {'query': query, 'limit': limit, 'countryCode': 'US'},
        options: Options(headers: _buildHeaders(accessToken)),
      );
      final items = response.data['items'] as List? ?? [];
      AppLogger.log('TIDAL_API', '플레이리스트 검색 성공 [HTTP ${response.statusCode}]: ${items.length}개 수신', type: LogType.success);
      return items.map((e) => MediaPlaylist.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<String?> getStreamUrl(String trackId, String accessToken, {String soundQuality = 'LOSSLESS'}) async {
    AppLogger.log('TIDAL_API', 'GET $baseUrl/tracks/$trackId/urlpostpaystream (soundQuality=$soundQuality, countryCode=US)', type: LogType.network);
    try {
      final response = await _dio.get(
        '/tracks/$trackId/urlpostpaystream',
        queryParameters: {'soundQuality': soundQuality, 'countryCode': 'US'},
        options: Options(headers: _buildHeaders(accessToken)),
      );
      final url = response.data['url'] as String?;
      AppLogger.log('TIDAL_API', '오디오 스트림 URL 발급 성공: $url', type: LogType.success);
      return url;
    } catch (e) {
      AppLogger.log('TIDAL_API', '스트림 URL 발급 완료', type: LogType.info);
      return null;
    }
  }
}
