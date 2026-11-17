import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tidal_connect_lite/core/providers.dart';
import 'package:tidal_connect_lite/features/dlna/data/dlna_manager.dart';
import 'package:tidal_connect_lite/features/dlna/data/ssdp_discovery_service.dart';
import 'package:tidal_connect_lite/features/dlna/domain/models/dlna_device.dart';
import 'package:tidal_connect_lite/features/player/data/player_manager.dart';
import 'package:tidal_connect_lite/features/tidal_api/data/tidal_api_client.dart';
import 'package:tidal_connect_lite/features/tidal_api/domain/models/media_item.dart';

import 'fakes.dart';

/// 네트워크 없이 빈 목록을 돌려주는 API 클라이언트. 호출된 메서드 이름을 기록한다.
class FakeApiClient extends TidalApiClient {
  FakeApiClient() : super();

  final List<String> calls = [];
  List<MediaTrack> tracks = const [];

  Future<List<T>> _empty<T>(String name) async {
    calls.add(name);
    return <T>[];
  }

  Future<PageResult<T>> _emptyPage<T>(String name, int offset) async {
    calls.add(name);
    return PageResult<T>(items: <T>[], offset: offset, total: 0, hasMore: false);
  }

  @override
  Future<PageResult<MediaAlbum>> getFavoriteAlbums({required String userId, int offset = 0, int limit = 50}) =>
      _emptyPage('getFavoriteAlbums', offset);
  @override
  Future<PageResult<MediaArtist>> getFavoriteArtists({required String userId, int offset = 0, int limit = 50}) =>
      _emptyPage('getFavoriteArtists', offset);
  @override
  Future<PageResult<MediaPlaylist>> getFavoritePlaylists({required String userId, int offset = 0, int limit = 50}) =>
      _emptyPage('getFavoritePlaylists', offset);
  @override
  Future<PageResult<MediaTrack>> getFavoriteTracks({required String userId, int offset = 0, int limit = 50}) async {
    calls.add('getFavoriteTracks');
    return PageResult(items: tracks, offset: offset, total: tracks.length, hasMore: false);
  }

  @override
  Future<List<MediaAlbum>> getFeaturedAlbums() => _empty('getFeaturedAlbums');
  @override
  Future<List<MediaPlaylist>> getFeaturedPlaylists() => _empty('getFeaturedPlaylists');
  @override
  Future<List<MediaTrack>> getFeaturedTracks() async {
    calls.add('getFeaturedTracks');
    return tracks;
  }

  @override
  Future<List<MediaTrack>> searchTracks(String query, {int limit = 20}) async {
    calls.add('searchTracks:$query');
    return tracks;
  }

  List<MediaAlbum> artistAlbums = const [];

  @override
  Future<List<MediaTrack>> getArtistTopTracks(String artistId, {int limit = 20}) async {
    calls.add('getArtistTopTracks:$artistId');
    return tracks;
  }

  @override
  Future<PageResult<MediaAlbum>> getArtistAlbums(String artistId, {int offset = 0, int limit = 50}) async {
    calls.add('getArtistAlbums:$artistId:$offset');
    return PageResult(items: artistAlbums, offset: offset, total: artistAlbums.length, hasMore: false);
  }

  final Map<FavoriteType, Set<String>> favoriteIds = {for (final t in FavoriteType.values) t: <String>{}};
  bool failFavoriteWrites = false;

  @override
  Future<Map<FavoriteType, Set<String>>> getFavoriteIds({required String userId}) async {
    calls.add('getFavoriteIds');
    return {
      for (final e in favoriteIds.entries) e.key: {...e.value}
    };
  }

  @override
  Future<void> addFavorite({required String userId, required FavoriteType type, required String id}) async {
    calls.add('addFavorite:${type.name}:$id');
    if (failFavoriteWrites) throw Exception('offline');
    favoriteIds[type]!.add(id);
  }

  @override
  Future<void> removeFavorite({required String userId, required FavoriteType type, required String id}) async {
    calls.add('removeFavorite:${type.name}:$id');
    if (failFavoriteWrites) throw Exception('offline');
    favoriteIds[type]!.remove(id);
  }

  @override
  Future<SearchResults> searchAll(String query, {int limit = 20}) async {
    calls.add('searchAll:$query');
    return SearchResults(tracks: tracks);
  }

  @override
  Future<List<MediaAlbum>> searchAlbums(String query, {int limit = 20}) => _empty('searchAlbums');
  @override
  Future<List<MediaPlaylist>> searchPlaylists(String query, {int limit = 20}) => _empty('searchPlaylists');

  /// 곡 ID별 스트림 정보. 여기에 없는 곡은 [defaultPlaybackInfo]를 쓴다(기본 null = 스트림 없음).
  final Map<String, TidalPlaybackInfo?> playbackInfos = {};
  TidalPlaybackInfo? defaultPlaybackInfo;

  /// 지정하면 [getPlaybackInfo]가 이 Completer가 끝날 때까지 응답을 미룬다.
  Completer<void>? playbackInfoGate;

  @override
  Future<TidalPlaybackInfo?> getPlaybackInfo(String trackId, {String quality = 'LOSSLESS'}) async {
    calls.add('getPlaybackInfo:$trackId:$quality');
    await playbackInfoGate?.future;
    return playbackInfos.containsKey(trackId) ? playbackInfos[trackId] : defaultPlaybackInfo;
  }
}

/// 소켓을 열지 않는 SSDP 탐색기. 기본은 폰 스피커만 돌려준다.
class FakeSsdpDiscoveryService extends SSDPDiscoveryService {
  int callCount = 0;

  /// 찾은 것으로 돌려줄 원격 기기. 실제 탐색기처럼 폰 스피커가 항상 맨 앞에 붙는다.
  List<DlnaDevice> devices = const [];

  /// 지정하면 탐색이 이 예외로 실패한다.
  Object? error;

  /// 지정하면 기기를 알린 뒤 이 Completer가 끝날 때까지 탐색 완료를 미룬다.
  Completer<void>? gate;

  @override
  Future<List<DlnaDevice>> discoverDevices({
    Duration timeout = const Duration(seconds: 4),
    void Function(DlnaDevice device)? onDeviceFound,
  }) async {
    callCount++;
    final found = [DlnaDevice.localSpeaker];
    for (final device in devices) {
      found.add(device);
      onDeviceFound?.call(device);
    }
    await gate?.future;
    final failure = error;
    if (failure != null) throw failure;
    return found;
  }
}

/// 위젯 테스트용 가짜 의존성 묶음.
class TestApp {
  TestApp() {
    SharedPreferences.setMockInitialValues({});
  }

  final auth = FakeAuthRepository();
  final api = FakeApiClient();
  final ssdp = FakeSsdpDiscoveryService();
  late final dlna = DlnaManager.forTesting(ssdpService: ssdp);
  final player = PlayerManager.forTesting();

  List<Override> get overrides => [
        authRepositoryProvider.overrideWithValue(auth),
        apiClientProvider.overrideWithValue(api),
        dlnaManagerProvider.overrideWithValue(dlna),
        playerManagerProvider.overrideWithValue(player),
      ];
}
