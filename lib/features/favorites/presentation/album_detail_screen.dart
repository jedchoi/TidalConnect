import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_logger.dart';
import '../../auth/data/tidal_auth_repository.dart';
import '../../player/data/player_manager.dart';
import '../../player/presentation/mini_player_widget.dart';
import '../../tidal_api/data/tidal_api_client.dart';
import '../../tidal_api/domain/models/media_item.dart';

class AlbumDetailScreen extends StatefulWidget {
  final MediaAlbum album;

  const AlbumDetailScreen({super.key, required this.album});

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  final TidalAuthRepository _authRepo = TidalAuthRepository();
  final TidalApiClient _apiClient = TidalApiClient();
  final PlayerManager _playerManager = PlayerManager.instance;

  bool _isLoading = true;
  List<MediaTrack> _tracks = [];

  @override
  void initState() {
    super.initState();
    _loadAlbumTracks();
  }

  Future<void> _loadAlbumTracks() async {
    setState(() => _isLoading = true);
    try {
      var token = await _authRepo.autoLogin();
      token ??= await _authRepo.authenticateClientCredentials();

      if (token != null) {
        final tracks = await _apiClient.getAlbumTracks(widget.album.id, token.accessToken);
        if (mounted) {
          setState(() {
            _tracks = tracks;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      AppLogger.log('ALBUM_DETAIL', '앨범 트랙 로딩 오류: $e', type: LogType.error);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _playAll() {
    if (_tracks.isNotEmpty) {
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.album.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                        // Album Cover Art
                        Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: widget.album.coverUrl.isNotEmpty
                                ? Image.network(
                                    widget.album.coverUrl,
                                    width: 200,
                                    height: 200,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => _buildFallbackCover(),
                                  )
                                : _buildFallbackCover(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Album Title
                        Text(
                          widget.album.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 6),
                        // Artist Name
                        Text(
                          widget.album.artistName,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 15, color: AppColors.cyanAccent, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        // Badge / Track count
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceLight,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppColors.cyanAccent.withOpacity(0.5)),
                              ),
                              child: const Text('MASTER • Hi-Res', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.cyanAccent)),
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
                      return ValueListenableBuilder<MediaTrack?>(
                        valueListenable: _playerManager.currentTrackNotifier,
                        builder: (context, currentTrack, _) {
                          final isCurrent = currentTrack?.id == track.id;
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            decoration: BoxDecoration(
                              color: isCurrent ? AppColors.cyanAccent.withOpacity(0.1) : AppColors.surfaceCard,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: isCurrent ? AppColors.cyanAccent : AppColors.surfaceLight),
                            ),
                            child: ListTile(
                              leading: SizedBox(
                                width: 28,
                                child: Center(
                                  child: isCurrent
                                      ? const Icon(Icons.equalizer, color: AppColors.cyanAccent, size: 20)
                                      : Text('${index + 1}', style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                                ),
                              ),
                              title: Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isCurrent ? AppColors.cyanAccent : Colors.white,
                                ),
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
                                        _playerManager.playTrack(track);
                                      }
                                    },
                                  ),
                                ],
                              ),
                              onTap: () => _playerManager.playTrack(track),
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

  Widget _buildFallbackCover() {
    return Container(
      width: 200,
      height: 200,
      color: AppColors.surfaceCard,
      child: const Center(child: Icon(Icons.album, size: 80, color: AppColors.cyanAccent)),
    );
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
