import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/error_retry_view.dart';
import '../../../core/widgets/track_tile.dart';
import '../../../core/utils/app_logger.dart';
import '../../favorites/presentation/album_detail_screen.dart';
import 'recently_played_section.dart';
import '../../favorites/presentation/playlist_artwork_widget.dart';
import '../../favorites/presentation/playlist_detail_screen.dart';
import '../../tidal_api/data/tidal_api_client.dart';
import '../../tidal_api/domain/models/media_item.dart';

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  TidalApiClient get _apiClient => ref.read(apiClientProvider);

  bool _isLoading = true;
  String? _errorMessage;
  List<MediaAlbum> _featuredAlbums = [];
  List<MediaPlaylist> _featuredPlaylists = [];
  List<MediaTrack> _featuredTracks = [];

  @override
  void initState() {
    super.initState();
    _loadExploreData();
  }

  Future<void> _loadExploreData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final results = await Future.wait([
        _apiClient.getFeaturedAlbums(),
        _apiClient.getFeaturedPlaylists(),
        _apiClient.getFeaturedTracks(),
      ]);

      if (mounted) {
        setState(() {
          _featuredAlbums = results[0] as List<MediaAlbum>;
          _featuredPlaylists = results[1] as List<MediaPlaylist>;
          _featuredTracks = results[2] as List<MediaTrack>;
          _isLoading = false;
        });
      }
    } catch (e) {
      AppLogger.log('EXPLORE', '추천 데이터 로딩 오류: $e', type: LogType.error);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e is ApiFailure ? e.message : '추천 목록을 불러오지 못했습니다.';
        });
      }
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
          : _errorMessage != null
              ? ErrorRetryView(message: _errorMessage!, onRetry: _loadExploreData)
              : RefreshIndicator(
                  onRefresh: _loadExploreData,
                  color: AppColors.cyanAccent,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // 0. 최근 재생
                      const RecentlyPlayedSection(),
                      // 1. 추천 앨범 (Master / Hi-Res)
                      if (_featuredAlbums.isNotEmpty) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '추천 신규 앨범',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            ),
                            Text('${_featuredAlbums.length}개',
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
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
                                                  child: const Center(
                                                      child: Icon(Icons.album, size: 40, color: AppColors.cyanAccent)),
                                                ),
                                              )
                                            : Container(
                                                height: 90,
                                                color: Colors.white10,
                                                child: const Center(
                                                    child: Icon(Icons.album, size: 40, color: AppColors.cyanAccent)),
                                              ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        album.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
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
                            Text('${_featuredPlaylists.length}개',
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
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
                              title: Text(playlist.title,
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
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
                            Text('${_featuredTracks.length}곡',
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...List.generate(_featuredTracks.length, (index) {
                          final track = _featuredTracks[index];
                          return TrackTile(track: track, queue: _featuredTracks, index: index);
                        }),
                      ],
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
    );
  }
}
