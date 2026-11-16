import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../core/utils/app_logger.dart';
import '../domain/models/media_item.dart';

class TidalPlaybackInfo {
  /// 단일 파일 스트림 주소(BTS). DASH면 빈 문자열.
  final String streamUrl;

  /// DASH MPD 원문. 단일 파일 스트림이면 빈 문자열.
  final String manifest;
  final String manifestMimeType;

  /// 실제 오디오 MIME(예: audio/flac, audio/mp4).
  final String mimeType;
  final String audioQuality;
  final int? bitDepth;
  final int? sampleRate;

  TidalPlaybackInfo({
    required this.streamUrl,
    required this.manifest,
    required this.manifestMimeType,
    required this.audioQuality,
    this.mimeType = 'audio/mp4',
    this.bitDepth,
    this.sampleRate,
  });

  bool get isDash => streamUrl.isEmpty && manifest.isNotEmpty;
}

/// 음질 단계. 요청한 음질이 안 되면 한 단계 아래로 한 번만 다시 시도한다.
const List<String> audioQualityLadder = ['HI_RES_LOSSLESS', 'LOSSLESS', 'HIGH', 'LOW'];

String? lowerAudioQuality(String quality) {
  final i = audioQualityLadder.indexOf(quality);
  return (i == -1 || i == audioQualityLadder.length - 1) ? null : audioQualityLadder[i + 1];
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

  /// 재생용 스트림 정보를 받는다. [quality]로 한 번 요청하고, 실패하면 한 단계 낮은 음질로 한 번 더 요청한다.
  Future<TidalPlaybackInfo?> getPlaybackInfo(String trackId, String accessToken, {String quality = 'LOSSLESS'}) async {
    final first = await _requestPlaybackInfo(trackId, accessToken, quality);
    if (first != null) return first;
    final lower = lowerAudioQuality(quality);
    if (lower == null) return null;
    AppLogger.log('TIDAL_API', '$quality 스트림 실패 -> $lower로 재시도', type: LogType.warning);
    return _requestPlaybackInfo(trackId, accessToken, lower);
  }

  Future<TidalPlaybackInfo?> _requestPlaybackInfo(String trackId, String accessToken, String quality) async {
    AppLogger.log('TIDAL_API', 'GET /tracks/$trackId/playbackinfopostpaywall (audioquality=$quality)', type: LogType.network);
    try {
      final response = await _dio.get(
        '/tracks/$trackId/playbackinfopostpaywall',
        queryParameters: {
          'audioquality': quality,
          'playbackmode': 'STREAM',
          'assetpresentation': 'FULL',
        },
        options: Options(headers: _buildHeaders(accessToken)),
      );
      final info = parsePlaybackInfo(response.data, fallbackQuality: quality);
      if (info == null) {
        AppLogger.log('TIDAL_API', '스트림 정보 해석 실패 ($quality)', type: LogType.warning);
      } else {
        AppLogger.log('TIDAL_API', '스트림 정보 수신: ${info.audioQuality}, ${info.isDash ? 'DASH' : info.mimeType}', type: LogType.success);
      }
      return info;
    } catch (e) {
      final status = e is DioException ? e.response?.statusCode : null;
      AppLogger.log('TIDAL_API', '스트림 정보 요청 실패 ($quality, HTTP $status)', type: LogType.warning);
      return null;
    }
  }

  /// playbackinfopostpaywall 응답을 해석한다. BTS(JSON)면 단일 주소를, DASH면 MPD 원문을 담는다.
  static TidalPlaybackInfo? parsePlaybackInfo(dynamic data, {required String fallbackQuality}) {
    if (data is! Map) return null;
    final manifest = data['manifest'] as String? ?? '';
    final manifestMimeType = data['manifestMimeType'] as String? ?? '';
    final quality = data['audioQuality'] as String? ?? fallbackQuality;
    final bitDepth = (data['bitDepth'] as num?)?.toInt();
    final sampleRate = (data['sampleRate'] as num?)?.toInt();
    if (manifest.isEmpty) return null;

    final String decoded;
    try {
      decoded = utf8.decode(base64.decode(manifest), allowMalformed: true);
    } catch (_) {
      return null;
    }

    if (manifestMimeType.contains('dash') || decoded.trimLeft().startsWith('<')) {
      return TidalPlaybackInfo(
        streamUrl: '',
        manifest: decoded,
        manifestMimeType: 'application/dash+xml',
        mimeType: 'audio/mp4',
        audioQuality: quality,
        bitDepth: bitDepth,
        sampleRate: sampleRate,
      );
    }

    try {
      final json = jsonDecode(decoded);
      if (json is! Map) return null;
      final urls = json['urls'];
      final url = (urls is List && urls.isNotEmpty) ? urls.first.toString() : (json['url']?.toString() ?? '');
      if (url.isEmpty) return null;
      final codecs = json['codecs']?.toString().toLowerCase() ?? '';
      return TidalPlaybackInfo(
        streamUrl: url,
        manifest: '',
        manifestMimeType: manifestMimeType,
        mimeType: json['mimeType']?.toString() ?? (codecs.contains('flac') ? 'audio/flac' : 'audio/mp4'),
        audioQuality: quality,
        bitDepth: bitDepth,
        sampleRate: sampleRate,
      );
    } catch (_) {
      return null;
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

  // ──────────────────────────────────────────────
  // 연관 추천곡 / Track Radio (Similar Tracks) Endpoints
  // ──────────────────────────────────────────────

  Future<List<MediaTrack>> getSimilarTracks(String trackId, String accessToken, {int limit = 30}) async {
    if (trackId.isEmpty) return [];
    AppLogger.log('TIDAL_API', 'GET $baseUrl/tracks/$trackId/similarTracks (countryCode=US, limit=$limit)', type: LogType.network);
    try {
      final response = await _dio.get(
        '/tracks/$trackId/similarTracks',
        queryParameters: {'countryCode': 'US', 'limit': limit},
        options: Options(headers: _buildHeaders(accessToken)),
      );
      final items = response.data['items'] as List? ?? [];
      if (items.isNotEmpty) {
        AppLogger.log('TIDAL_API', '연관 추천곡(similarTracks) 수신 성공: ${items.length}개', type: LogType.success);
        return items.map((e) => MediaTrack.fromJson(e is Map<String, dynamic> ? e : {})).toList();
      }
    } catch (e) {
      AppLogger.log('TIDAL_API', 'similarTracks 조회 실패 ($e) -> 추천곡 폴백 시도', type: LogType.warning);
    }

    // 폴백: /tracks/$trackId/radio 또는 추천 트랙
    try {
      final response = await _dio.get(
        '/tracks/$trackId/radio',
        queryParameters: {'countryCode': 'US', 'limit': limit},
        options: Options(headers: _buildHeaders(accessToken)),
      );
      final items = response.data['items'] as List? ?? [];
      if (items.isNotEmpty) {
        return items.map((e) => MediaTrack.fromJson(e is Map<String, dynamic> ? e : {})).toList();
      }
    } catch (_) {}

    return getFeaturedTracks(accessToken);
  }
}

