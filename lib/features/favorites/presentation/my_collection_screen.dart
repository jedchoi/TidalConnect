import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/paginator.dart';
import '../../../core/widgets/load_more_indicator.dart';
import '../../../core/widgets/track_tile.dart';
import '../../tidal_api/data/tidal_api_client.dart';
import '../../tidal_api/domain/models/media_item.dart';
import '../../artist/presentation/artist_detail_screen.dart';
import 'album_detail_screen.dart';
import 'playlist_artwork_widget.dart';
import 'playlist_detail_screen.dart';

class MyCollectionScreen extends ConsumerStatefulWidget {
  const MyCollectionScreen({super.key});

  @override
  ConsumerState<MyCollectionScreen> createState() => _MyCollectionScreenState();
}

class _MyCollectionScreenState extends ConsumerState<MyCollectionScreen> {
  TidalApiClient get _apiClient => ref.read(apiClientProvider);

  bool _isLoading = true;
  bool _isLoggedIn = false;
  String? _errorMessage;
  String _userId = '';
  late final Paginator<MediaAlbum> _albums =
      Paginator((offset) => _apiClient.getFavoriteAlbums(userId: _userId, offset: offset));
  late final Paginator<MediaArtist> _artists =
      Paginator((offset) => _apiClient.getFavoriteArtists(userId: _userId, offset: offset));
  late final Paginator<MediaPlaylist> _playlists =
      Paginator((offset) => _apiClient.getFavoritePlaylists(userId: _userId, offset: offset));
  late final Paginator<MediaTrack> _tracks =
      Paginator((offset) => _apiClient.getFavoriteTracks(userId: _userId, offset: offset));

  @override
  void initState() {
    super.initState();
    _loadCollectionData();
  }

  @override
  void dispose() {
    _albums.dispose();
    _artists.dispose();
    _playlists.dispose();
    _tracks.dispose();
    super.dispose();
  }

  Future<void> _loadCollectionData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final userToken = await ref.read(authRepositoryProvider).autoLogin();

      if (userToken == null || userToken.userId.isEmpty) {
        _albums.clear();
        _artists.clear();
        _playlists.clear();
        _tracks.clear();
        if (mounted) {
          setState(() {
            _isLoggedIn = false;
            _isLoading = false;
            _errorMessage = 'Tidal 로그인이 필요합니다.\n설정 탭에서 로그인해 주세요.';
          });
        }
        return;
      }

      _isLoggedIn = true;
      _userId = userToken.userId;

      await Future.wait([_albums.refresh(), _artists.refresh(), _playlists.refresh(), _tracks.refresh()]);

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      AppLogger.log('FAVORITES', '컬렉션 로딩 오류: $e', type: LogType.error);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e is ApiFailure ? e.message : '즐겨찾기를 불러오지 못했습니다.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 로그인·로그아웃·계정 변경 시 즐겨찾기를 자동으로 다시 불러온다.
    ref.listen<String?>(loggedInUserIdProvider, (previous, next) {
      if (previous != next) _loadCollectionData();
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('내 즐겨찾기', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.surfaceCard,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.cyanAccent),
            tooltip: '새로고침',
            onPressed: _loadCollectionData,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.cyanAccent));
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isLoggedIn ? Icons.cloud_off : Icons.login,
                size: 64,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 15),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadCollectionData,
                icon: const Icon(Icons.refresh),
                label: const Text('다시 시도'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyanAccent,
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListenableBuilder(
      listenable: Listenable.merge([_albums, _artists, _playlists, _tracks]),
      builder: (context, _) => _buildCollection(),
    );
  }

  Widget _buildCollection() {
    final albums = _albums.items;
    final artists = _artists.items;
    final playlists = _playlists.items;
    final tracks = _tracks.items;
    final bool isEmpty = albums.isEmpty && artists.isEmpty && playlists.isEmpty && tracks.isEmpty;
    if (isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.library_music, size: 64, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            const Text(
              '즐겨찾기가 비어있습니다.\nTidal 앱에서 좋아하는 음악을 추가해보세요!',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadCollectionData,
              icon: const Icon(Icons.refresh),
              label: const Text('새로고침'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.cyanAccent,
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCollectionData,
      color: AppColors.cyanAccent,
      child: NotificationListener<ScrollNotification>(
        // 세로 목록 끝에 닿으면 트랙 다음 페이지를 받는다.
        onNotification: _tracks.onScroll,
        child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. 내 앨범 섹션
          if (albums.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '내 앨범',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                Text('${_albums.totalCount}개', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 175,
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) => _albums.onScroll(n, axis: Axis.horizontal),
                child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: albums.length + (_albums.hasMore ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  if (index == albums.length) return LoadMoreIndicator(paginator: _albums, width: 60);
                  final album = albums[index];
                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => AlbumDetailScreen(album: album)),
                      );
                    },
                    child: Container(
                      width: 130,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.surfaceLight),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: album.coverUrl.isNotEmpty
                                ? Image.network(
                                    album.coverUrl,
                                    width: 114,
                                    height: 90,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      height: 90,
                                      color: Colors.white10,
                                      child: const Center(child: Icon(Icons.album, size: 40, color: AppColors.cyanAccent)),
                                    ),
                                  )
                                : Container(
                                    height: 90,
                                    color: Colors.white10,
                                    child: const Center(child: Icon(Icons.album, size: 40, color: AppColors.cyanAccent)),
                                  ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            album.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                          ),
                          Text(
                            album.artistName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // 2. 내 아티스트 섹션
          if (artists.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '내 아티스트',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                Text('${_artists.totalCount}명', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) => _artists.onScroll(n, axis: Axis.horizontal),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: artists.length + (_artists.hasMore ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    if (index == artists.length) return LoadMoreIndicator(paginator: _artists, width: 60);
                    return _ArtistAvatar(artist: artists[index]);
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // 3. 내 플레이리스트 섹션
          if (playlists.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '내 플레이리스트',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                Text('${_playlists.totalCount}개', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 12),
            ...List.generate(playlists.length, (index) {
              final playlist = playlists[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  tileColor: AppColors.surfaceCard,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(color: AppColors.surfaceLight),
                  ),
                  leading: PlaylistArtworkWidget(
                    coverUrl: playlist.coverUrl,
                    size: 48,
                    borderRadius: 8,
                  ),
                  title: Text(playlist.title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  subtitle: Text(
                    playlist.numberOfTracks > 0 ? '${playlist.numberOfTracks}곡' : playlist.description,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => PlaylistDetailScreen(playlist: playlist)),
                    );
                  },
                ),
              );
            }),
            if (_playlists.hasMore) LoadMoreIndicator(paginator: _playlists, asButton: true),
            const SizedBox(height: 24),
          ],

          // 4. 내 트랙 섹션
          if (tracks.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '내 트랙',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                Text('${_tracks.totalCount}곡', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 12),
            ...List.generate(tracks.length, (index) {
              final track = tracks[index];
              return TrackTile(track: track, queue: tracks, index: index);
            }),
            if (_tracks.hasMore) LoadMoreIndicator(paginator: _tracks),
          ],
          const SizedBox(height: 80),
        ],
      ),
      ),
    );
  }
}

class _ArtistAvatar extends StatelessWidget {
  final MediaArtist artist;
  const _ArtistAvatar({required this.artist});

  @override
  Widget build(BuildContext context) {
    const fallback = CircleAvatar(
      radius: 40,
      backgroundColor: AppColors.surfaceCard,
      child: Icon(Icons.person, size: 36, color: AppColors.cyanAccent),
    );
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ArtistDetailScreen(artist: artist))),
      child: SizedBox(
        width: 84,
        child: Column(
          children: [
            artist.pictureUrl.isEmpty
                ? fallback
                : ClipOval(
                    child: Image.network(
                      artist.pictureUrl,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => fallback,
                    ),
                  ),
            const SizedBox(height: 6),
            Text(
              artist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
