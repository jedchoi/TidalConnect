import 'package:dio/dio.dart';
import '../../../core/utils/app_logger.dart';
import '../domain/models/media_item.dart';

class TidalApiClient {
  final Dio _dio;
  // v1 API (legacy) - catalog search 등 일부 기능용
  static const String baseUrl = 'https://api.tidal.com/v1';
  // v2 OpenAPI - user collection (favorites) 등 현대 API용
  static const String v2BaseUrl = 'https://openapi.tidal.com/v2';

  TidalApiClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
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

  /// v2 API용 헤더 (JSON:API 규격)
  Map<String, String> _buildV2Headers(String accessToken) {
    return {
      'Authorization': 'Bearer $accessToken',
      'Accept': 'application/vnd.api+json',
      'Content-Type': 'application/vnd.api+json',
    };
  }

  // ──────────────────────────────────────────────
  // v2 OpenAPI - User Collection (Favorites)
  // ──────────────────────────────────────────────

  Future<List<MediaAlbum>> getFavoriteAlbums(String accessToken, {String userId = 'me'}) async {
    // 1차: v2 OpenAPI 시도
    final v2Albums = await _getFavoriteAlbumsV2(accessToken);
    if (v2Albums.isNotEmpty) return v2Albums;

    // 2차: v1 레거시 API 폴백
    return _getFavoriteAlbumsV1(accessToken, userId: userId);
  }

  Future<List<MediaPlaylist>> getFavoritePlaylists(String accessToken, {String userId = 'me'}) async {
    final v2Playlists = await _getFavoritePlaylistsV2(accessToken);
    if (v2Playlists.isNotEmpty) return v2Playlists;
    return _getFavoritePlaylistsV1(accessToken, userId: userId);
  }

  Future<List<MediaTrack>> getFavoriteTracks(String accessToken, {String userId = 'me'}) async {
    final v2Tracks = await _getFavoriteTracksV2(accessToken);
    if (v2Tracks.isNotEmpty) return v2Tracks;
    return _getFavoriteTracksV1(accessToken, userId: userId);
  }

  // ── v2 구현 ──

  Future<List<MediaAlbum>> _getFavoriteAlbumsV2(String accessToken) async {
    final endpoint = '$v2BaseUrl/userCollectionAlbums/me';
    AppLogger.log('TIDAL_API', 'GET $endpoint (v2 OpenAPI)', type: LogType.network);
    try {
      final response = await _dio.get(
        endpoint,
        queryParameters: {'countryCode': 'US', 'include': 'items'},
        options: Options(headers: _buildV2Headers(accessToken)),
      );
      final data = response.data;
      // JSON:API 응답 형식: { data: { relationships: { items: { data: [...] } } }, included: [...] }
      final included = data['included'] as List? ?? [];
      final albums = <MediaAlbum>[];
      for (final item in included) {
        if (item['type'] == 'albums') {
          final attrs = item['attributes'] ?? {};
          albums.add(MediaAlbum(
            id: item['id']?.toString() ?? '',
            title: attrs['title'] ?? '',
            artistName: _extractArtistName(attrs),
            coverUrl: _extractCoverUrl(attrs),
            numberOfTracks: attrs['numberOfTracks'] ?? 0,
          ));
        }
      }
      if (albums.isNotEmpty) {
        AppLogger.log('TIDAL_API', 'v2 즐겨찾기 앨범 수신 성공: ${albums.length}개', type: LogType.success);
      }
      return albums;
    } catch (e) {
      if (e is DioException && e.response != null) {
        AppLogger.log('TIDAL_API', 'v2 즐겨찾기 앨범 실패 [HTTP ${e.response?.statusCode}]: ${e.response?.data}', type: LogType.warning);
      } else {
        AppLogger.log('TIDAL_API', 'v2 즐겨찾기 앨범 실패: $e', type: LogType.warning);
      }
      return [];
    }
  }

  Future<List<MediaPlaylist>> _getFavoritePlaylistsV2(String accessToken) async {
    final endpoint = '$v2BaseUrl/userCollectionPlaylists/me';
    AppLogger.log('TIDAL_API', 'GET $endpoint (v2 OpenAPI)', type: LogType.network);
    try {
      final response = await _dio.get(
        endpoint,
        queryParameters: {'countryCode': 'US', 'include': 'items'},
        options: Options(headers: _buildV2Headers(accessToken)),
      );
      final data = response.data;
      final included = data['included'] as List? ?? [];
      final playlists = <MediaPlaylist>[];
      for (final item in included) {
        if (item['type'] == 'playlists') {
          final attrs = item['attributes'] ?? {};
          playlists.add(MediaPlaylist(
            id: item['id']?.toString() ?? '',
            title: attrs['title'] ?? attrs['name'] ?? '',
            description: attrs['description'] ?? '',
            coverUrl: _extractCoverUrl(attrs),
            numberOfTracks: attrs['numberOfTracks'] ?? 0,
          ));
        }
      }
      if (playlists.isNotEmpty) {
        AppLogger.log('TIDAL_API', 'v2 즐겨찾기 플레이리스트 수신 성공: ${playlists.length}개', type: LogType.success);
      }
      return playlists;
    } catch (e) {
      if (e is DioException && e.response != null) {
        AppLogger.log('TIDAL_API', 'v2 즐겨찾기 플레이리스트 실패 [HTTP ${e.response?.statusCode}]: ${e.response?.data}', type: LogType.warning);
      } else {
        AppLogger.log('TIDAL_API', 'v2 즐겨찾기 플레이리스트 실패: $e', type: LogType.warning);
      }
      return [];
    }
  }

  Future<List<MediaTrack>> _getFavoriteTracksV2(String accessToken) async {
    final endpoint = '$v2BaseUrl/userCollectionTracks/me';
    AppLogger.log('TIDAL_API', 'GET $endpoint (v2 OpenAPI)', type: LogType.network);
    try {
      final response = await _dio.get(
        endpoint,
        queryParameters: {'countryCode': 'US', 'include': 'items'},
        options: Options(headers: _buildV2Headers(accessToken)),
      );
      final data = response.data;
      final included = data['included'] as List? ?? [];
      final tracks = <MediaTrack>[];
      for (final item in included) {
        if (item['type'] == 'tracks') {
          final attrs = item['attributes'] ?? {};
          tracks.add(MediaTrack(
            id: item['id']?.toString() ?? '',
            title: attrs['title'] ?? '',
            artistName: _extractArtistName(attrs),
            albumTitle: attrs['albumTitle'] ?? '',
            durationSeconds: attrs['duration'] ?? 0,
            coverUrl: _extractCoverUrl(attrs),
          ));
        }
      }
      if (tracks.isNotEmpty) {
        AppLogger.log('TIDAL_API', 'v2 즐겨찾기 트랙 수신 성공: ${tracks.length}개', type: LogType.success);
      }
      return tracks;
    } catch (e) {
      if (e is DioException && e.response != null) {
        AppLogger.log('TIDAL_API', 'v2 즐겨찾기 트랙 실패 [HTTP ${e.response?.statusCode}]: ${e.response?.data}', type: LogType.warning);
      } else {
        AppLogger.log('TIDAL_API', 'v2 즐겨찾기 트랙 실패: $e', type: LogType.warning);
      }
      return [];
    }
  }

  /// JSON:API attributes에서 아티스트 이름 추출
  String _extractArtistName(Map<String, dynamic> attrs) {
    if (attrs['artistName'] != null) return attrs['artistName'];
    if (attrs['artists'] != null && attrs['artists'] is List && (attrs['artists'] as List).isNotEmpty) {
      return attrs['artists'][0]['name'] ?? '';
    }
    return '';
  }

  /// JSON:API attributes에서 커버 이미지 URL 추출
  String _extractCoverUrl(Map<String, dynamic> attrs) {
    if (attrs['imageLinks'] != null && attrs['imageLinks'] is List && (attrs['imageLinks'] as List).isNotEmpty) {
      return attrs['imageLinks'][0]['href'] ?? '';
    }
    if (attrs['squareImage'] != null && attrs['squareImage'] is List && (attrs['squareImage'] as List).isNotEmpty) {
      return attrs['squareImage'][0]['url'] ?? '';
    }
    if (attrs['cover'] != null) {
      final cover = attrs['cover'].toString();
      if (cover.startsWith('http')) return cover;
      // TIDAL cover ID format: UUID → URL
      return 'https://resources.tidal.com/images/${cover.replaceAll('-', '/')}/320x320.jpg';
    }
    return '';
  }

  // ── v1 레거시 폴백 (scope 필요 시 실패할 수 있음) ──

  Future<List<MediaAlbum>> _getFavoriteAlbumsV1(String accessToken, {String userId = 'me'}) async {
    final effectiveUserId = userId.isEmpty ? 'me' : userId;
    final endpoint = '/users/$effectiveUserId/favorites/albums';
    AppLogger.log('TIDAL_API', 'GET $baseUrl$endpoint (v1 레거시 폴백)', type: LogType.network);
    try {
      final response = await _dio.get(
        '$baseUrl$endpoint',
        queryParameters: {'countryCode': 'US', 'limit': 50},
        options: Options(headers: _buildHeaders(accessToken)),
      );
      final items = response.data['items'] as List? ?? [];
      AppLogger.log('TIDAL_API', 'v1 즐겨찾기 앨범 수신 성공 [HTTP ${response.statusCode}]: ${items.length}개', type: LogType.success);
      return items.map((e) => MediaAlbum.fromJson(e['item'] ?? e)).toList();
    } catch (e) {
      if (e is DioException && e.response != null) {
        AppLogger.log('TIDAL_API', 'v1 즐겨찾기 앨범 실패 [HTTP ${e.response?.statusCode}]: ${e.response?.data}', type: LogType.info);
      }
      return [];
    }
  }

  Future<List<MediaPlaylist>> _getFavoritePlaylistsV1(String accessToken, {String userId = 'me'}) async {
    final effectiveUserId = userId.isEmpty ? 'me' : userId;
    final endpoint = '/users/$effectiveUserId/favorites/playlists';
    AppLogger.log('TIDAL_API', 'GET $baseUrl$endpoint (v1 레거시 폴백)', type: LogType.network);
    try {
      final response = await _dio.get(
        '$baseUrl$endpoint',
        queryParameters: {'countryCode': 'US', 'limit': 50},
        options: Options(headers: _buildHeaders(accessToken)),
      );
      final items = response.data['items'] as List? ?? [];
      AppLogger.log('TIDAL_API', 'v1 즐겨찾기 플레이리스트 수신 성공 [HTTP ${response.statusCode}]: ${items.length}개', type: LogType.success);
      return items.map((e) => MediaPlaylist.fromJson(e['playlist'] ?? e)).toList();
    } catch (e) {
      if (e is DioException && e.response != null) {
        AppLogger.log('TIDAL_API', 'v1 즐겨찾기 플레이리스트 실패 [HTTP ${e.response?.statusCode}]: ${e.response?.data}', type: LogType.info);
      }
      return [];
    }
  }

  Future<List<MediaTrack>> _getFavoriteTracksV1(String accessToken, {String userId = 'me'}) async {
    final effectiveUserId = userId.isEmpty ? 'me' : userId;
    final endpoint = '/users/$effectiveUserId/favorites/tracks';
    AppLogger.log('TIDAL_API', 'GET $baseUrl$endpoint (v1 레거시 폴백)', type: LogType.network);
    try {
      final response = await _dio.get(
        '$baseUrl$endpoint',
        queryParameters: {'countryCode': 'US', 'limit': 50},
        options: Options(headers: _buildHeaders(accessToken)),
      );
      final items = response.data['items'] as List? ?? [];
      AppLogger.log('TIDAL_API', 'v1 즐겨찾기 트랙 수신 성공 [HTTP ${response.statusCode}]: ${items.length}개', type: LogType.success);
      return items.map((e) => MediaTrack.fromJson(e['item'] ?? e)).toList();
    } catch (e) {
      if (e is DioException && e.response != null) {
        AppLogger.log('TIDAL_API', 'v1 즐겨찾기 트랙 실패 [HTTP ${e.response?.statusCode}]: ${e.response?.data}', type: LogType.info);
      }
      return [];
    }
  }

  // ──────────────────────────────────────────────
  // 기타 API (아티스트, 검색, 스트림)
  // ──────────────────────────────────────────────

  Future<List<MediaArtist>> getFavoriteArtists(String accessToken, {String userId = 'me'}) async {
    final effectiveUserId = userId.isEmpty ? 'me' : userId;
    final endpoint = '/users/$effectiveUserId/favorites/artists';
    AppLogger.log('TIDAL_API', 'GET $baseUrl$endpoint (countryCode=US)', type: LogType.network);
    try {
      final response = await _dio.get(
        '$baseUrl$endpoint',
        queryParameters: {'countryCode': 'US', 'limit': 50},
        options: Options(headers: _buildHeaders(accessToken)),
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
    AppLogger.log('TIDAL_API', 'GET $baseUrl/search/tracks (query=$query, countryCode=US)', type: LogType.network);
    try {
      final response = await _dio.get(
        '$baseUrl/search/tracks',
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
        '$baseUrl/search/albums',
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
        '$baseUrl/search/playlists',
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
        '$baseUrl/tracks/$trackId/urlpostpaystream',
        queryParameters: {'soundQuality': soundQuality, 'countryCode': 'US'},
        options: Options(headers: _buildHeaders(accessToken)),
      );
      final url = response.data['url'] as String?;
      AppLogger.log('TIDAL_API', '오디오 스트림 URL 발급 성공: $url', type: LogType.success);
      return url;
    } catch (e) {
      AppLogger.log('TIDAL_API', '스트림 URL 발급 실패', type: LogType.info);
      return null;
    }
  }
}
