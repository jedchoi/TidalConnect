import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/data/tidal_auth_repository.dart';
import '../../player/data/player_manager.dart';
import '../../tidal_api/data/tidal_api_client.dart';
import '../../tidal_api/domain/models/media_item.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TidalAuthRepository _authRepo = TidalAuthRepository();
  final TidalApiClient _apiClient = TidalApiClient();
  final PlayerManager _playerManager = PlayerManager.instance;

  Timer? _debounce;
  bool _isSearching = false;
  List<MediaTrack> _searchTracks = [];

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      if (mounted) setState(() => _searchTracks = []);
      return;
    }
    setState(() => _isSearching = true);
    try {
      var token = await _authRepo.autoLogin();
      token ??= await _authRepo.authenticateClientCredentials();

      if (token != null) {
        final tracks = await _apiClient.searchTracks(query, token.accessToken);
        if (mounted) {
          setState(() => _searchTracks = tracks);
        }
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('음악 검색', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.surfaceCard,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: '아티스트, 곡, 앨범 검색 (예: Queen, Master)',
                hintStyle: const TextStyle(color: AppColors.textSecondary),
                prefixIcon: const Icon(Icons.search, color: AppColors.cyanAccent),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white54),
                        onPressed: () {
                          _searchController.clear();
                          _performSearch('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.surfaceCard,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isSearching
                  ? const Center(child: CircularProgressIndicator(color: AppColors.cyanAccent))
                  : _searchTracks.isEmpty
                      ? Center(
                          child: Text(
                            _searchController.text.isEmpty ? '검색어를 입력하세요' : '검색 결과가 없습니다',
                            style: const TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _searchTracks.length,
                          itemBuilder: (context, index) {
                            final track = _searchTracks[index];
                            return ValueListenableBuilder<MediaTrack?>(
                              valueListenable: _playerManager.currentTrackNotifier,
                              builder: (context, currentTrack, _) {
                                final isCurrent = currentTrack?.id == track.id;
                                return Card(
                                  color: isCurrent ? AppColors.cyanAccent.withOpacity(0.1) : AppColors.surfaceCard,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    side: BorderSide(color: isCurrent ? AppColors.cyanAccent : AppColors.surfaceLight),
                                  ),
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    leading: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: track.coverUrl.isNotEmpty
                                          ? Image.network(
                                              track.coverUrl,
                                              width: 44,
                                              height: 44,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => const Icon(Icons.music_note, color: AppColors.cyanAccent),
                                            )
                                          : const Icon(Icons.music_note, color: AppColors.cyanAccent),
                                    ),
                                    title: Text(
                                      track.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isCurrent ? AppColors.cyanAccent : Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
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
                                          _playerManager.playTrack(track);
                                        }
                                      },
                                    ),
                                    onTap: () {
                                      _playerManager.playTrack(track);
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
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
