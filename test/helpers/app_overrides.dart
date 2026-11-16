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

  @override
  Future<List<MediaAlbum>> searchAlbums(String query, {int limit = 20}) => _empty('searchAlbums');
  @override
  Future<List<MediaPlaylist>> searchPlaylists(String query, {int limit = 20}) => _empty('searchPlaylists');
}

/// 소켓을 열지 않고 폰 스피커만 돌려주는 SSDP 탐색기.
class FakeSsdpDiscoveryService extends SSDPDiscoveryService {
  int callCount = 0;

  @override
  Future<List<DlnaDevice>> discoverDevices({
    Duration timeout = const Duration(seconds: 4),
    void Function(DlnaDevice device)? onDeviceFound,
  }) async {
    callCount++;
    return [DlnaDevice.localSpeaker];
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
