import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/paginator.dart';
import '../../../core/widgets/error_retry_view.dart';
import '../../../core/widgets/load_more_indicator.dart';
import '../../../core/widgets/track_tile.dart';
import '../../../core/utils/app_logger.dart';
import '../../player/data/player_manager.dart';
import '../../player/presentation/mini_player_widget.dart';
import '../../tidal_api/data/tidal_api_client.dart';
import '../../tidal_api/domain/models/media_item.dart';
import 'playlist_artwork_widget.dart';

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  final MediaPlaylist playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  ConsumerState<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  TidalApiClient get _apiClient => ref.read(apiClientProvider);
  PlayerManager get _playerManager => ref.read(playerManagerProvider);

  bool _isLoading = true;
  String? _errorMessage;
  late final Paginator<MediaTrack> _pager = Paginator((offset) => _apiClient.getPlaylistTracks(widget.playlist.id, offset: offset));
  List<MediaTrack> get _tracks => _pager.items;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadPlaylistTracks();
  }

  Future<void> _loadPlaylistTracks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await _pager.refresh();
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      AppLogger.log('PLAYLIST_DETAIL', '플레이리스트 트랙 로딩 오류: $e', type: LogType.error);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e is ApiFailure ? e.message : '플레이리스트 트랙을 불러오지 못했습니다.';
        });
      }
    }
  }

  void _playAll() {
    if (_tracks.isNotEmpty) {
      _playerManager.setQueue(_tracks, startIndex: 0);
      _playerManager.playTrack(_tracks.first);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${_tracks.first.title}" 재생을 시작합니다.'),
          backgroundColor: AppColors.cyanAccent,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final trackCovers = _tracks.map((t) => t.coverUrl).where((c) => c.isNotEmpty).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.playlist.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: AppColors.surfaceCard,
        elevation: 0,
      ),
      bottomNavigationBar: const MiniPlayerWidget(autoStartDiscovery: false, useSafeArea: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.cyanAccent))
          : _errorMessage != null
              ? ErrorRetryView(message: _errorMessage!, onRetry: _loadPlaylistTracks)
              : ListenableBuilder(
                  listenable: _pager,
                  builder: (context, _) => NotificationListener<ScrollNotification>(
                    onNotification: _pager.onScroll,
                    child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        // Combined 4-tile Collage Artwork
                        Center(
                          child: PlaylistArtworkWidget(
                            coverUrl: widget.playlist.coverUrl,
                            trackCoverUrls: trackCovers,
                            size: 180,
                            borderRadius: 16,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Playlist Title
                        Text(
                          widget.playlist.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        if (widget.playlist.description.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            widget.playlist.description,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceLight,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('PLAYLIST', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.cyanAccent)),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '총 ${_pager.totalCount}곡',
                              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // Play All Button
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _playAll,
                                icon: const Icon(Icons.play_arrow, color: Colors.black),
                                label: const Text('전체 재생', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.cyanAccent,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
                // Track list
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final track = _tracks[index];
                      return TrackTile(
                        track: track,
                        queue: _tracks,
                        index: index,
                        subtitle: track.artistName,
                        showDuration: true,
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leadingBuilder: (isCurrent) => SizedBox(
                          width: 28,
                          child: Center(
                            child: isCurrent
                                ? const Icon(Icons.equalizer, color: AppColors.cyanAccent, size: 20)
                                : Text('${index + 1}', style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      );
                    },
                    childCount: _tracks.length,
                  ),
                ),
                if (_pager.hasMore) SliverToBoxAdapter(child: LoadMoreIndicator(paginator: _pager)),
                const SliverToBoxAdapter(child: SizedBox(height: 80)),
              ],
            ),
                  ),
                ),
    );
  }

}
