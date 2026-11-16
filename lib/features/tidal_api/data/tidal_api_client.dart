import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../core/utils/app_logger.dart';
import '../../auth/data/tidal_auth_repository.dart';
import '../domain/models/media_item.dart';
import 'api_failure.dart';
import 'auth_interceptor.dart';

export 'api_failure.dart';

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
  static const String _countryCode = 'US';

  /// [authRepository]가 있으면 [AuthInterceptor]가 모든 요청에 토큰을 붙이고 401이면 한 번 갱신해 재시도한다.
  TidalApiClient({TidalAuthRepository? authRepository, Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 8),
                headers: {'Accept': 'application/json'},
              ),
            ) {
    if (authRepository != null) {
      _dio.interceptors.add(AuthInterceptor(authRepository, _dio));
    }
  }

  // ──────────────────────────────────────────────
  // 공통
  // ──────────────────────────────────────────────

  Future<dynamic> _get(String path, Map<String, dynamic> query) async {
    AppLogger.log('TIDAL_API', 'GET $path', type: LogType.network);
    try {
      final response = await _dio.get(path, queryParameters: {'countryCode': _countryCode, ...query});
      return response.data;
    } on DioException catch (e) {
      final failure = ApiFailure.fromDio(e);
      AppLogger.log('TIDAL_API', 'GET $path 실패: ${failure.kind.name} (HTTP ${failure.statusCode})', type: LogType.error);
      throw failure;
    }
  }

  static List<T> _items<T>(dynamic data, T Function(Map<String, dynamic>) parse) {
    if (data is! Map) throw const ApiFailure(ApiFailureKind.parse, '응답 형식이 올바르지 않습니다.');
    final items = data['items'];
    if (items is! List) return const [];
    return items.whereType<Map>().map((e) => parse(Map<String, dynamic>.from(e))).toList();
  }

  // ──────────────────────────────────────────────
  // 즐겨찾기
  // ──────────────────────────────────────────────

  Future<List<MediaAlbum>> getFavoriteAlbums({required String userId}) async =>
      _items(await _get('/users/$userId/favorites/albums', {'limit': 50}), MediaAlbum.fromJson);

  Future<List<MediaPlaylist>> getFavoritePlaylists({required String userId}) async =>
      _items(await _get('/users/$userId/favorites/playlists', {'limit': 50}), MediaPlaylist.fromJson);

  Future<List<MediaTrack>> getFavoriteTracks({required String userId}) async =>
      _items(await _get('/users/$userId/favorites/tracks', {'limit': 50}), MediaTrack.fromJson);

  // ──────────────────────────────────────────────
  // 앨범·플레이리스트 트랙
  // ──────────────────────────────────────────────

  Future<List<MediaTrack>> getAlbumTracks(String albumId) async =>
      _items(await _get('/albums/$albumId/tracks', {'limit': 100}), MediaTrack.fromJson);

  /// 플레이리스트 트랙. /tracks가 비거나 실패하면 /items를 시도한다.
  Future<List<MediaTrack>> getPlaylistTracks(String playlistId) async {
    try {
      final tracks = _items(await _get('/playlists/$playlistId/tracks', {'limit': 100}), MediaTrack.fromJson);
      if (tracks.isNotEmpty) return tracks;
    } on ApiFailure catch (e) {
      if (e.kind == ApiFailureKind.network) rethrow;
    }
    return _items(await _get('/playlists/$playlistId/items', {'limit': 100}), MediaTrack.fromJson);
  }

  // ──────────────────────────────────────────────
  // 재생 정보
  // ──────────────────────────────────────────────

  /// 재생용 스트림 정보를 받는다. [quality]로 한 번 요청하고, 실패하면 한 단계 낮은 음질로 한 번 더 요청한다.
  Future<TidalPlaybackInfo?> getPlaybackInfo(String trackId, {String quality = 'LOSSLESS'}) async {
    final first = await _requestPlaybackInfo(trackId, quality);
    if (first != null) return first;
    final lower = lowerAudioQuality(quality);
    if (lower == null) return null;
    AppLogger.log('TIDAL_API', '$quality 스트림 실패 -> $lower로 재시도', type: LogType.warning);
    return _requestPlaybackInfo(trackId, lower);
  }

  Future<TidalPlaybackInfo?> _requestPlaybackInfo(String trackId, String quality) async {
    try {
      final data = await _get('/tracks/$trackId/playbackinfopostpaywall', {
        'audioquality': quality,
        'playbackmode': 'STREAM',
        'assetpresentation': 'FULL',
      });
      final info = parsePlaybackInfo(data, fallbackQuality: quality);
      if (info != null) {
        AppLogger.log('TIDAL_API', '스트림 정보 수신: ${info.audioQuality}, ${info.isDash ? 'DASH' : info.mimeType}', type: LogType.success);
      }
      return info;
    } on ApiFailure {
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
  // 추천
  // ──────────────────────────────────────────────

  /// 추천 신규 앨범. 비어 있거나 실패하면 검색 결과로 대신한다.
  Future<List<MediaAlbum>> getFeaturedAlbums() => _withFallback(
        () async => _items(await _get('/featured/new/albums', {'limit': 20}), MediaAlbum.fromJson),
        () => searchAlbums('Master', limit: 10),
      );

  Future<List<MediaPlaylist>> getFeaturedPlaylists() => _withFallback(
        () async => _items(await _get('/featured/recommended/playlists', {'limit': 20}), MediaPlaylist.fromJson),
        () => searchPlaylists('Tidal Master', limit: 10),
      );

  Future<List<MediaTrack>> getFeaturedTracks() => _withFallback(
        () async => _items(await _get('/featured/recommended/tracks', {'limit': 20}), MediaTrack.fromJson),
        () => searchTracks('Top Hits', limit: 15),
      );

  Future<List<T>> _withFallback<T>(Future<List<T>> Function() primary, Future<List<T>> Function() fallback) async {
    try {
      final items = await primary();
      if (items.isNotEmpty) return items;
    } on ApiFailure catch (e) {
      if (e.kind == ApiFailureKind.network) rethrow;
    }
    return fallback();
  }

  // ──────────────────────────────────────────────
  // 검색
  // ──────────────────────────────────────────────

  Future<List<MediaTrack>> searchTracks(String query, {int limit = 20}) async {
    if (query.trim().isEmpty) return const [];
    return _items(await _get('/search/tracks', {'query': query, 'limit': limit}), MediaTrack.fromJson);
  }

  Future<List<MediaAlbum>> searchAlbums(String query, {int limit = 20}) async {
    if (query.trim().isEmpty) return const [];
    return _items(await _get('/search/albums', {'query': query, 'limit': limit}), MediaAlbum.fromJson);
  }

  Future<List<MediaPlaylist>> searchPlaylists(String query, {int limit = 20}) async {
    if (query.trim().isEmpty) return const [];
    return _items(await _get('/search/playlists', {'query': query, 'limit': limit}), MediaPlaylist.fromJson);
  }

  // ──────────────────────────────────────────────
  // 연관 추천곡
  // ──────────────────────────────────────────────

  /// 유사곡. similarTracks -> radio -> 추천 트랙 순으로 시도한다.
  Future<List<MediaTrack>> getSimilarTracks(String trackId, {int limit = 30}) async {
    if (trackId.isEmpty) return const [];
    return _withFallback(
      () async => _items(await _get('/tracks/$trackId/similarTracks', {'limit': limit}), MediaTrack.fromJson),
      () => _withFallback(
        () async => _items(await _get('/tracks/$trackId/radio', {'limit': limit}), MediaTrack.fromJson),
        getFeaturedTracks,
      ),
    );
  }
}
