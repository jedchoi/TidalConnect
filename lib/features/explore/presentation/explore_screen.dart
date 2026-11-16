import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_logger.dart';
import '../../favorites/presentation/album_detail_screen.dart';
import '../../favorites/presentation/playlist_artwork_widget.dart';
import '../../favorites/presentation/playlist_detail_screen.dart';
import '../../player/data/player_manager.dart';
import '../../tidal_api/data/tidal_api_client.dart';
import '../../tidal_api/domain/models/media_item.dart';

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  TidalApiClient get _apiClient => ref.read(apiClientProvider);
  PlayerManager get _playerManager => ref.read(playerManagerProvider);

  bool _isLoading = true;
  List<MediaAlbum> _featuredAlbums = [];
  List<MediaPlaylist> _featuredPlaylists = [];
  List<MediaTrack> _featuredTracks = [];

  @override
  void initState() {
    super.initState();
    _loadExploreData();
  }

  Future<void> _loadExploreData() async {
    setState(() => _isLoading = true);
    try {
      final accessToken = await ref.read(authRepositoryProvider).getCatalogToken();

      if (accessToken != null) {
        final results = await Future.wait([
          _apiClient.getFeaturedAlbums(accessToken),
          _apiClient.getFeaturedPlaylists(accessToken),
          _apiClient.getFeaturedTracks(accessToken),
        ]);

        if (mounted) {
          setState(() {
            _featuredAlbums = results[0] as List<MediaAlbum>;
            _featuredPlaylists = results[1] as List<MediaPlaylist>;
            _featuredTracks = results[2] as List<MediaTrack>;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      AppLogger.log('EXPLORE', '추천 데이터 로딩 오류: $e', type: LogType.error);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('추천 & 탐색', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.surfaceCard,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.cyanAccent),
            tooltip: '새로고침',
            onPressed: _loadExploreData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.cyanAccent))
          : RefreshIndicator(
              onRefresh: _loadExploreData,
              color: AppColors.cyanAccent,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // 1. 추천 앨범 (Master / Hi-Res)
                  if (_featuredAlbums.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '추천 신규 앨범',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
                        Text('${_featuredAlbums.length}개', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 175,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _featuredAlbums.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final album = _featuredAlbums[index];
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

                  // 2. 추천 플레이리스트 & 믹스
                  if (_featuredPlaylists.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'TIDAL 추천 플레이리스트',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
                        Text('${_featuredPlaylists.length}개', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...List.generate(_featuredPlaylists.length, (index) {
                      final playlist = _featuredPlaylists[index];
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

                  // 3. 인기 추천 트랙
                  if (_featuredTracks.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '인기 추천 트랙',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
                        Text('${_featuredTracks.length}곡', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...List.generate(_featuredTracks.length, (index) {
                      final track = _featuredTracks[index];
                      return ListenableBuilder(
                        // 현재 곡과 재생 상태가 바뀔 때마다 아이콘을 다시 그린다.
                        listenable: Listenable.merge([_playerManager.currentTrackNotifier, _playerManager.isPlayingNotifier]),
                        builder: (context, _) {
                          final currentTrack = _playerManager.currentTrack;
                          final isCurrent = currentTrack?.id == track.id;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              tileColor: isCurrent ? AppColors.cyanAccent.withOpacity(0.1) : AppColors.surfaceCard,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(color: isCurrent ? AppColors.cyanAccent : AppColors.surfaceLight),
                              ),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: track.coverUrl.isNotEmpty
                                    ? Image.network(track.coverUrl, width: 44, height: 44, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.music_note, color: AppColors.cyanAccent))
                                    : const Icon(Icons.music_note, color: AppColors.cyanAccent),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      track.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isCurrent ? AppColors.cyanAccent : Colors.white,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: track.isMax ? Colors.amber.withOpacity(0.2) : AppColors.surfaceLight,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      track.qualityBadgeText,
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: track.isMax ? Colors.amberAccent : AppColors.cyanAccent,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                '${track.artistName} • ${track.albumTitle}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                              ),
                              trailing: IconButton(
                                icon: Icon(
                                  isCurrent && _playerManager.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                                  color: AppColors.cyanAccent,
                                ),
                                onPressed: () {
                                  if (isCurrent) {
                                    _playerManager.togglePlayPause();
                                  } else {
                                    final idx = _featuredTracks.indexOf(track);
                                    _playerManager.playTrack(track, queue: _featuredTracks, index: idx != -1 ? idx : 0);
                                  }
                                },
                              ),
                              onTap: () {
                                final idx = _featuredTracks.indexOf(track);
                                _playerManager.playTrack(track, queue: _featuredTracks, index: idx != -1 ? idx : 0);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('"${track.title}" 재생을 시작합니다.'),
                                    backgroundColor: AppColors.cyanAccent,
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      );
                    }),
                  ],
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }
}
