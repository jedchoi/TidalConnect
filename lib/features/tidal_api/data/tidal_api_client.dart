import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../core/utils/app_logger.dart';
import '../domain/models/media_item.dart';

class TidalPlaybackInfo {
  final String streamUrl;
  final String manifest;
  final String manifestMimeType;
  final String audioQuality;

  TidalPlaybackInfo({
    required this.streamUrl,
    required this.manifest,
    required this.manifestMimeType,
    required this.audioQuality,
  });
}

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
      return items.map((e) => MediaAlbum.fromJson(e is Map<String, dynamic> ? e : {})).toList();
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
      return items.map((e) => MediaPlaylist.fromJson(e is Map<String, dynamic> ? e : {})).toList();
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
      return items.map((e) => MediaTrack.fromJson(e is Map<String, dynamic> ? e : {})).toList();
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
      return items.map((e) => MediaTrack.fromJson(e is Map<String, dynamic> ? e : {})).toList();
    } catch (e) {
      AppLogger.log('TIDAL_API', '앨범 트랙 수신 오류: $e', type: LogType.error);
      return [];
    }
  }

  Future<List<MediaTrack>> getPlaylistTracks(String playlistId, String accessToken) async {
    AppLogger.log('TIDAL_API', '플레이리스트($playlistId) 트랙 조회 시작...', type: LogType.network);
    
    // 1차: /playlists/$playlistId/tracks 시도
    try {
      final response = await _dio.get(
        '/playlists/$playlistId/tracks',
        queryParameters: {'countryCode': 'US', 'limit': 100},
        options: Options(headers: _buildHeaders(accessToken)),
      );
      final items = response.data['items'] as List? ?? [];
      if (items.isNotEmpty) {
        AppLogger.log('TIDAL_API', '플레이리스트 트랙 목록 수신 성공 (/tracks) [HTTP ${response.statusCode}]: ${items.length}개', type: LogType.success);
        return items.map((e) => MediaTrack.fromJson(e is Map<String, dynamic> ? e : {})).toList();
      }
    } catch (e) {
      AppLogger.log('TIDAL_API', '/playlists/$playlistId/tracks 조회 예외: $e ➔ /items 엔드포인트 시도', type: LogType.warning);
    }

    // 2차: /playlists/$playlistId/items 시도
    try {
      final response = await _dio.get(
        '/playlists/$playlistId/items',
        queryParameters: {'countryCode': 'US', 'limit': 100},
        options: Options(headers: _buildHeaders(accessToken)),
      );
      final items = response.data['items'] as List? ?? [];
      AppLogger.log('TIDAL_API', '플레이리스트 트랙 목록 수신 성공 (/items) [HTTP ${response.statusCode}]: ${items.length}개', type: LogType.success);
      return items.map((e) => MediaTrack.fromJson(e is Map<String, dynamic> ? e : {})).toList();
    } catch (e) {
      AppLogger.log('TIDAL_API', '/playlists/$playlistId/items 조회 실패: $e', type: LogType.error);
      return [];
    }
  }

  // ──────────────────────────────────────────────
  // 실시간 재생 정보 (MPEG-DASH MPD 및 오디오 스트림 URL) 발급
  // ──────────────────────────────────────────────

  Future<TidalPlaybackInfo?> getPlaybackInfo(String trackId, String accessToken, {String soundQuality = 'HIGH'}) async {
    final qualities = [soundQuality, 'HIGH', 'LOSSLESS', 'LOW'];

    // 1. playbackinfopostpaywall 호출
    for (final q in qualities.toSet()) {
      try {
        AppLogger.log('TIDAL_API', 'GET $baseUrl/tracks/$trackId/playbackinfopostpaywall (audioquality=$q)', type: LogType.network);
        final response = await _dio.get(
          '/tracks/$trackId/playbackinfopostpaywall',
          queryParameters: {
            'audioquality': q,
            'playbackmode': 'STREAM',
            'assetpresentation': 'FULL',
          },
          options: Options(headers: _buildHeaders(accessToken)),
        );

        final data = response.data;
        if (data is Map<String, dynamic>) {
          final manifest = data['manifest'] as String? ?? '';
          final manifestMimeType = data['manifestMimeType'] as String? ?? 'application/dash+xml';
          final quality = data['audioQuality'] as String? ?? q;

          if (manifest.isNotEmpty) {
            try {
              final decodedBytes = base64.decode(manifest);
              final decodedStr = utf8.decode(decodedBytes, allowMalformed: true).replaceAll('&amp;', '&');

              if (decodedStr.trim().startsWith('{')) {
                // BTS / EMU JSON Format
                final decodedJson = jsonDecode(decodedStr);
                String streamUrl = '';
                if (decodedJson is Map && decodedJson['urls'] is List && (decodedJson['urls'] as List).isNotEmpty) {
                  streamUrl = (decodedJson['urls'] as List).first.toString().replaceAll('&amp;', '&');
                } else if (decodedJson is Map && decodedJson['url'] != null) {
                  streamUrl = decodedJson['url'].toString().replaceAll('&amp;', '&');
                }
                AppLogger.log('TIDAL_API', 'JSON 매니페스트 추출 성공: $streamUrl', type: LogType.success);
                return TidalPlaybackInfo(
                  streamUrl: streamUrl,
                  manifest: decodedStr,
                  manifestMimeType: manifestMimeType,
                  audioQuality: quality,
                );
              } else {
                // MPEG-DASH MPD XML Format
                AppLogger.log('TIDAL_API', 'DASH MPD 매니페스트 추출 성공 (${decodedStr.length}자)', type: LogType.success);
                return TidalPlaybackInfo(
                  streamUrl: '',
                  manifest: decodedStr,
                  manifestMimeType: 'application/dash+xml',
                  audioQuality: quality,
                );
              }
            } catch (e) {
              AppLogger.log('TIDAL_API', '매니페스트 디코딩 예외: $e', type: LogType.warning);
            }
          }

          if (data['url'] != null && data['url'].toString().isNotEmpty) {
            final directUrl = data['url'].toString().replaceAll('&amp;', '&');
            return TidalPlaybackInfo(
              streamUrl: directUrl,
              manifest: '',
              manifestMimeType: 'audio/mp4',
              audioQuality: quality,
            );
          }
        }
      } catch (e) {
        AppLogger.log('TIDAL_API', 'playbackinfopostpaywall ($q) 시도 실패: $e', type: LogType.warning);
      }
    }

    // 2. 트랙 상세 메타데이터 폴백
    try {
      final response = await _dio.get(
        '/tracks/$trackId',
        queryParameters: {'countryCode': 'US'},
        options: Options(headers: _buildHeaders(accessToken)),
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        if (data['previewUrl'] != null && data['previewUrl'].toString().isNotEmpty) {
          final url = data['previewUrl'].toString().replaceAll('&amp;', '&');
          return TidalPlaybackInfo(
            streamUrl: url,
            manifest: '',
            manifestMimeType: 'audio/mp4',
            audioQuality: 'PREVIEW',
          );
        }
      }
    } catch (_) {}

    return null;
  }

  Future<String?> getStreamUrl(String trackId, String accessToken, {String soundQuality = 'HIGH'}) async {
    final info = await getPlaybackInfo(trackId, accessToken, soundQuality: soundQuality);
    if (info != null && info.streamUrl.isNotEmpty) {
      return info.streamUrl;
    }
    return null;
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
        return items.map((e) => MediaAlbum.fromJson(e is Map<String, dynamic> ? e : {})).toList();
      }
    } catch (_) {}

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
        return items.map((e) => MediaPlaylist.fromJson(e is Map<String, dynamic> ? e : {})).toList();
      }
    } catch (_) {}

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
        return items.map((e) => MediaTrack.fromJson(e is Map<String, dynamic> ? e : {})).toList();
      }
    } catch (_) {}

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
      return items.map((e) => MediaTrack.fromJson(e is Map<String, dynamic> ? e : {})).toList();
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
      return items.map((e) => MediaAlbum.fromJson(e is Map<String, dynamic> ? e : {})).toList();
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
      return items.map((e) => MediaPlaylist.fromJson(e is Map<String, dynamic> ? e : {})).toList();
    } catch (e) {
      return [];
    }
  }
}
