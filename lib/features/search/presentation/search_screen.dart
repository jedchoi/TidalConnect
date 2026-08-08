import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/data/tidal_auth_repository.dart';
import '../../tidal_api/data/tidal_api_client.dart';
import '../../tidal_api/domain/models/media_item.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _isSearching = false;
  List<MediaTrack> _searchTracks = [];

  final TidalAuthRepository _authRepo = TidalAuthRepository();
  final TidalApiClient _apiClient = TidalApiClient();

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
      appBar: AppBar(
        title: const Text('음악 검색', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.background,
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
                hintText: '아티스트, 곡, 앨범 검색 (예: Queen, Jazz)',
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
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
