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

  static String _extractUrlFromDashMpd(String mpdXml) {
    try {
      // 1. <BaseURL> 태그 검색 (TIDAL DASH 매니페스트의 완전한 단일 오디오 파일 URL)
      final baseMatches = RegExp(r'<BaseURL[^>]*>(https?:\/\/[^<]+)<\/BaseURL>', caseSensitive: false).allMatches(mpdXml);
      for (final match in baseMatches) {
        final url = match.group(1)!.trim().replaceAll('&amp;', '&');
        // $Number$, $Time$, $Bandwidth$ 같은 템플릿 변수가 없는 완전한 URL만 채택
        if (!url.contains('\$Number') && !url.contains('\$Time') && !url.contains('\$Bandwidth')) {
          AppLogger.log('TIDAL_API', 'DASH 완전한 BaseURL 추출 성공: $url', type: LogType.success);
          return url;
        }
      }
    } catch (e) {
      AppLogger.log('TIDAL_API', 'DASH MPD XML 파싱 예외: $e', type: LogType.warning);
    }
    return '';
  }

  Future<TidalPlaybackInfo?> getPlaybackInfo(String trackId, String accessToken, {String soundQuality = 'HI_RES_LOSSLESS'}) async {
    // 🎧 최고 음질(MAX / Hi-Res Lossless -> FLAC Lossless -> High -> Low) 우선 시도
    final qualities = ['HI_RES_LOSSLESS', 'LOSSLESS', soundQuality, 'HIGH', 'LOW'];
    TidalPlaybackInfo? fallbackDASHInfo;

    // 1. DRM-Free Direct FLAC/AAC JSON 규격 (application/vnd.tidal.bts / emu) 우선 요청
    final manifestMimeTypes = ['application/vnd.tidal.bts', 'application/vnd.tidal.emu', 'application/dash+xml'];
    for (final q in qualities.toSet()) {
      for (final mime in manifestMimeTypes) {
        try {
          AppLogger.log('TIDAL_API', 'GET $baseUrl/tracks/$trackId/playbackinfopostpaywall (audioquality=$q, mime=$mime)', type: LogType.network);
          final response = await _dio.get(
            '/tracks/$trackId/playbackinfopostpaywall',
            queryParameters: {
              'audioquality': q,
              'playbackmode': 'STREAM',
              'assetpresentation': 'FULL',
              'manifestMimeType': mime,
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
                  if (streamUrl.isNotEmpty) {
                    AppLogger.log('TIDAL_API', 'JSON 매니페스트 추출 성공: $streamUrl', type: LogType.success);
                    return TidalPlaybackInfo(
                      streamUrl: streamUrl,
                      manifest: decodedStr,
                      manifestMimeType: manifestMimeType,
                      audioQuality: quality,
                    );
                  }
                } else {
                  // MPEG-DASH MPD XML Format -> BaseURL 추출 시도
                  final extractedUrl = _extractUrlFromDashMpd(decodedStr);
                  if (extractedUrl.isNotEmpty) {
                    return TidalPlaybackInfo(
                      streamUrl: extractedUrl,
                      manifest: decodedStr,
                      manifestMimeType: 'application/dash+xml',
                      audioQuality: quality,
                    );
                  } else {
                    AppLogger.log('TIDAL_API', 'DASH MPD 매니페스트 수신 ($q) - BaseURL 미발견, 다른 품질 폴백 시도', type: LogType.info);
                    fallbackDASHInfo ??= TidalPlaybackInfo(
                      streamUrl: '',
                      manifest: decodedStr,
                      manifestMimeType: 'application/dash+xml',
                      audioQuality: quality,
                    );
                  }
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
          AppLogger.log('TIDAL_API', 'playbackinfopostpaywall ($q, $mime) 시도 실패: $e', type: LogType.warning);
        }
      }
    }

    // DASH 폴백 정보가 있으면 반환
    if (fallbackDASHInfo != null) {
      return fallbackDASHInfo;
    }

    // 2. /tracks/$trackId/streamUrl 시도
    try {
      final response = await _dio.get(
        '/tracks/$trackId/streamUrl',
        queryParameters: {'countryCode': 'US', 'soundQuality': 'HIGH'},
        options: Options(headers: _buildHeaders(accessToken)),
      );
      final url = response.data['url']?.toString().replaceAll('&amp;', '&') ?? '';
      if (url.isNotEmpty) {
        AppLogger.log('TIDAL_API', '/streamUrl 엔드포인트 URL 획득 성공: $url', type: LogType.success);
        return TidalPlaybackInfo(
          streamUrl: url,
          manifest: '',
          manifestMimeType: 'audio/mp4',
          audioQuality: 'HIGH',
        );
      }
    } catch (_) {}

    // 3. 트랙 상세 메타데이터 previewUrl 폴백
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

    return fallbackDASHInfo;
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

