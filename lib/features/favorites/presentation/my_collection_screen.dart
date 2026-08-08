import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/data/tidal_auth_repository.dart';
import '../../tidal_api/data/tidal_api_client.dart';
import '../../tidal_api/domain/models/media_item.dart';

class MyCollectionScreen extends StatefulWidget {
  final bool autoLoad;

  const MyCollectionScreen({super.key, this.autoLoad = true});

  @override
  State<MyCollectionScreen> createState() => _MyCollectionScreenState();
}

class _MyCollectionScreenState extends State<MyCollectionScreen> {
  bool _isLoading = false;
  List<MediaAlbum> _albums = [];
  List<MediaPlaylist> _playlists = [];
  List<MediaTrack> _tracks = [];

  final TidalAuthRepository _authRepo = TidalAuthRepository();
  final TidalApiClient _apiClient = TidalApiClient();

  @override
  void initState() {
    super.initState();
    if (widget.autoLoad) {
      _loadCollectionData();
    }
  }

  Future<void> _loadCollectionData() async {
    setState(() => _isLoading = true);
    try {
      var token = await _authRepo.autoLogin();
      token ??= await _authRepo.authenticateClientCredentials();

      if (token != null) {
        var albums = await _apiClient.getFavoriteAlbums(token.accessToken);
        var playlists = await _apiClient.getFavoritePlaylists(token.accessToken);
        var tracks = await _apiClient.getFavoriteTracks(token.accessToken);

        // Fallback to catalog search if user favorites return empty
        if (albums.isEmpty) {
          albums = await _apiClient.searchAlbums('Master', token.accessToken);
        }
        if (playlists.isEmpty) {
          playlists = await _apiClient.searchPlaylists('Tidal', token.accessToken);
        }
        if (tracks.isEmpty) {
          tracks = await _apiClient.searchTracks('Top', token.accessToken);
        }

        if (mounted) {
          setState(() {
            _albums = albums;
            _playlists = playlists;
            _tracks = tracks;
          });
        }
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('내 즐겨찾기', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.background,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.cyanAccent),
            onPressed: _loadCollectionData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.cyanAccent),
            )
          : RefreshIndicator(
              color: AppColors.cyanAccent,
              onRefresh: _loadCollectionData,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  const Text(
                    '즐겨찾기 앨범',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.cyanAccent),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 160,
                    child: _albums.isEmpty
                        ? const Center(child: Text('앨범이 없습니다', style: TextStyle(color: AppColors.textSecondary)))
                        : ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _albums.length,
                            itemBuilder: (context, index) {
                              final album = _albums[index];
                              return Container(
                                width: 120,
                                margin: const EdgeInsets.only(right: 12),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceCard,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                        child: album.coverUrl.isNotEmpty
                                            ? Image.network(
                                                album.coverUrl,
                                                width: double.infinity,
                                                fit: BoxFit.cover,
                                                errorBuilder: (ctx, err, stack) => const Icon(Icons.album, color: Colors.white54, size: 48),
                                              )
                                            : const Center(child: Icon(Icons.album, color: Colors.white54, size: 48)),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(6.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            album.title,
                                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            album.artistName,
                                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '내 플레이리스트 / 추천 트랙',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.cyanAccent),
                  ),
                  const SizedBox(height: 12),
                  _playlists.isEmpty && _tracks.isEmpty
                      ? const Center(child: Text('음원 목록이 없습니다', style: TextStyle(color: AppColors.textSecondary)))
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _playlists.isNotEmpty ? _playlists.length : _tracks.length,
                          itemBuilder: (context, index) {
                            if (_playlists.isNotEmpty) {
                              final playlist = _playlists[index];
                              return Card(
                                color: AppColors.surfaceCard,
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: playlist.coverUrl.isNotEmpty
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(6),
                                          child: Image.network(playlist.coverUrl, width: 44, height: 44, fit: BoxFit.cover),
                                        )
                                      : const Icon(Icons.playlist_play, color: AppColors.cyanAccent),
                                  title: Text(playlist.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  subtitle: Text(playlist.description.isNotEmpty ? playlist.description : 'Tidal Playlist (${playlist.numberOfTracks}곡)', style: const TextStyle(color: AppColors.textSecondary)),
                                  trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                                ),
                              );
                            } else {
                              final track = _tracks[index];
                              return Card(
                                color: AppColors.surfaceCard,
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: track.coverUrl.isNotEmpty
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(6),
                                          child: Image.network(track.coverUrl, width: 44, height: 44, fit: BoxFit.cover),
                                        )
                                      : const Icon(Icons.music_note, color: AppColors.cyanAccent),
                                  title: Text(track.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  subtitle: Text('${track.artistName} • ${track.albumTitle}', style: const TextStyle(color: AppColors.textSecondary)),
                                  trailing: const Icon(Icons.play_circle_fill, color: AppColors.cyanAccent),
                                ),
                              );
                            }
                          },
                        ),
                ],
              ),
            ),
    );
  }
}
