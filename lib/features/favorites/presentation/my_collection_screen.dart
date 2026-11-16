import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_logger.dart';
import '../../tidal_api/data/tidal_api_client.dart';
import '../../tidal_api/domain/models/media_item.dart';
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
  List<MediaAlbum> _albums = [];
  List<MediaPlaylist> _playlists = [];
  List<MediaTrack> _tracks = [];

  @override
  void initState() {
    super.initState();
    _loadCollectionData();
  }

  Future<void> _loadCollectionData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final userToken = await ref.read(authRepositoryProvider).autoLogin();

      if (userToken == null || userToken.userId.isEmpty) {
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
      final userId = userToken.userId;

      final results = await Future.wait([
        _apiClient.getFavoriteAlbums(userId: userId),
        _apiClient.getFavoritePlaylists(userId: userId),
        _apiClient.getFavoriteTracks(userId: userId),
      ]);

      if (mounted) {
        setState(() {
          _albums = results[0] as List<MediaAlbum>;
          _playlists = results[1] as List<MediaPlaylist>;
          _tracks = results[2] as List<MediaTrack>;
          _isLoading = false;
        });
      }
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

    final bool isEmpty = _albums.isEmpty && _playlists.isEmpty && _tracks.isEmpty;
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
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. 내 앨범 섹션
          if (_albums.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '내 앨범',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                Text('${_albums.length}개', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 175,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _albums.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final album = _albums[index];
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
            const SizedBox(height: 24),
          ],

          // 2. 내 플레이리스트 섹션
          if (_playlists.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '내 플레이리스트',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                Text('${_playlists.length}개', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 12),
            ...List.generate(_playlists.length, (index) {
              final playlist = _playlists[index];
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
            const SizedBox(height: 24),
          ],

          // 3. 내 트랙 섹션
          if (_tracks.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '내 트랙',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                Text('${_tracks.length}곡', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 12),
            ...List.generate(_tracks.length, (index) {
              final track = _tracks[index];
              return TrackTile(track: track, queue: _tracks, index: index);
            }),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}
