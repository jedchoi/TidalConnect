import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
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
  List<MediaTrack> _tracks = [];

  @override
  void initState() {
    super.initState();
    _loadPlaylistTracks();
  }

  Future<void> _loadPlaylistTracks() async {
    setState(() => _isLoading = true);
    try {
      final tracks = await _apiClient.getPlaylistTracks(widget.playlist.id);
      if (mounted) {
        setState(() {
          _tracks = tracks;
          _isLoading = false;
        });
      }
    } catch (e) {
      AppLogger.log('PLAYLIST_DETAIL', '플레이리스트 트랙 로딩 오류: $e', type: LogType.error);
      if (mounted) setState(() => _isLoading = false);
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
          : CustomScrollView(
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
                              '총 ${_tracks.length}곡',
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
                      return ListenableBuilder(
                        // 현재 곡과 재생 상태가 바뀔 때마다 아이콘을 다시 그린다.
                        listenable: Listenable.merge([_playerManager.currentTrackNotifier, _playerManager.isPlayingNotifier]),
                        builder: (context, _) {
                          final currentTrack = _playerManager.currentTrack;
                          final isCurrent = currentTrack?.id == track.id;
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            decoration: BoxDecoration(
                              color: isCurrent ? AppColors.cyanAccent.withOpacity(0.1) : AppColors.surfaceCard,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: isCurrent ? AppColors.cyanAccent : AppColors.surfaceLight),
                            ),
                            child: ListTile(
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
                                track.artistName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _formatDuration(track.durationSeconds),
                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: Icon(
                                      isCurrent && _playerManager.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                                      color: AppColors.cyanAccent,
                                    ),
                                    onPressed: () {
                                      if (isCurrent) {
                                        _playerManager.togglePlayPause();
                                      } else {
                                        final idx = _tracks.indexOf(track);
                                        _playerManager.setQueue(_tracks, startIndex: idx);
                                        _playerManager.playTrack(track);
                                      }
                                    },
                                  ),
                                ],
                              ),
                              onTap: () {
                                final idx = _tracks.indexOf(track);
                                _playerManager.setQueue(_tracks, startIndex: idx);
                                _playerManager.playTrack(track);
                              },
                            ),
                          );
                        },
                      );
                    },
                    childCount: _tracks.length,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 80)),
              ],
            ),
    );
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
