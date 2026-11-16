import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/error_retry_view.dart';
import '../../../core/widgets/track_tile.dart';
import '../../tidal_api/data/tidal_api_client.dart';
import '../../favorites/presentation/album_detail_screen.dart';
import '../../favorites/presentation/playlist_artwork_widget.dart';
import '../../favorites/presentation/playlist_detail_screen.dart';
import '../data/search_history_store.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  TidalApiClient get _apiClient => ref.read(apiClientProvider);
  final SearchHistoryStore _historyStore = SearchHistoryStore();
  List<String> _history = [];

  Timer? _debounce;
  int _searchSeq = 0;
  bool _isSearching = false;
  SearchResults _results = const SearchResults();
  SearchCategory _category = SearchCategory.tracks;
  String? _searchError;

  @override
  void initState() {
    super.initState();
    _loadSearchHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadSearchHistory() async {
    try {
      final list = await _historyStore.load();
      if (mounted) setState(() => _history = list);
    } catch (_) {}
  }

  /// 입력 중 디바운스 검색은 기록하지 않고, 제출하거나 결과를 고를 때만 남긴다.
  Future<void> _saveSearchHistory(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    setState(() => _history = SearchHistoryStore.addToHistory(_history, trimmed));
    try {
      await _historyStore.add(_history, trimmed);
    } catch (_) {}
  }

  Future<void> _removeHistoryItem(String item) async {
    final before = _history;
    setState(() => _history = [...before]..remove(item));
    try {
      await _historyStore.remove(before, item);
    } catch (_) {}
  }

  Future<void> _clearAllHistory() async {
    setState(() => _history = []);
    try {
      await _historyStore.clear();
    } catch (_) {}
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _performSearch(query);
    });
  }

  void _submitSearch(String query) {
    _debounce?.cancel();
    _saveSearchHistory(query);
    _performSearch(query);
  }

  Future<void> _performSearch(String query) async {
    // 늦게 도착한 이전 검색 결과가 최신 결과를 덮어쓰지 않도록 요청 번호로 거른다.
    final seq = ++_searchSeq;
    if (query.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _results = const SearchResults();
          _searchError = null;
          _isSearching = false;
        });
      }
      return;
    }
    setState(() {
      _isSearching = true;
      _searchError = null;
    });
    try {
      final results = await _apiClient.searchAll(query);
      if (mounted && seq == _searchSeq) {
        setState(() => _results = results);
      }
    } catch (e) {
      if (mounted && seq == _searchSeq) {
        setState(() => _searchError = e is ApiFailure ? e.message : '검색하지 못했습니다.');
      }
    } finally {
      if (mounted && seq == _searchSeq) {
        setState(() => _isSearching = false);
      }
    }
  }

  void _searchWithQuery(String query) {
    _searchController.text = query;
    _submitSearch(query);
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _searchController.text.trim().isNotEmpty;

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
              textInputAction: TextInputAction.search,
              onSubmitted: _submitSearch,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: '곡, 앨범, 아티스트, 플레이리스트 검색',
                hintStyle: const TextStyle(color: AppColors.textSecondary),
                prefixIcon: const Icon(Icons.search, color: AppColors.cyanAccent),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white54),
                        onPressed: () {
                          _debounce?.cancel();
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
                  : hasQuery
                      ? _buildSearchResults()
                      : _buildSearchHistory(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchHistory() {
    if (_history.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: AppColors.surfaceLight),
            SizedBox(height: 16),
            Text(
              '검색어를 입력하여 TIDAL의 1억 곡 이상을 감상하세요',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '최근 검색어',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            TextButton(
              onPressed: _clearAllHistory,
              child: const Text('전체 삭제', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _history.map((query) {
            return Chip(
              backgroundColor: AppColors.surfaceCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: AppColors.surfaceLight),
              ),
              label: InkWell(
                onTap: () => _searchWithQuery(query),
                child: Text(query, style: const TextStyle(color: Colors.white, fontSize: 13)),
              ),
              deleteIcon: const Icon(Icons.close, size: 16, color: AppColors.textSecondary),
              onDeleted: () => _removeHistoryItem(query),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSearchResults() {
    if (_searchError != null) {
      return ErrorRetryView(message: _searchError!, onRetry: () => _performSearch(_searchController.text));
    }
    if (_results.isEmpty) {
      return const Center(
        child: Text(
          '검색 결과가 없습니다',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final c in SearchCategory.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('${c.label} ${_countOf(c)}'),
                    selected: _category == c,
                    onSelected: (_) => setState(() => _category = c),
                    selectedColor: AppColors.cyanAccent,
                    backgroundColor: AppColors.surfaceCard,
                    labelStyle: TextStyle(color: _category == c ? Colors.black : Colors.white, fontSize: 13),
                    showCheckmark: false,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(child: _buildCategoryList()),
      ],
    );
  }

  int _countOf(SearchCategory c) => switch (c) {
        SearchCategory.tracks => _results.tracks.length,
        SearchCategory.albums => _results.albums.length,
        SearchCategory.artists => _results.artists.length,
        SearchCategory.playlists => _results.playlists.length,
      };

  void _remember() => _saveSearchHistory(_searchController.text);

  Widget _buildCategoryList() {
    if (_countOf(_category) == 0) {
      return Center(
        child: Text('${_category.label} 결과가 없습니다', style: const TextStyle(color: AppColors.textSecondary)),
      );
    }
    switch (_category) {
      case SearchCategory.tracks:
        final tracks = _results.tracks;
        return ListView.builder(
          itemCount: tracks.length,
          itemBuilder: (context, index) => TrackTile(
            track: tracks[index],
            queue: tracks,
            index: index,
            onPlay: _remember,
          ),
        );
      case SearchCategory.albums:
        final albums = _results.albums;
        return ListView.builder(
          itemCount: albums.length,
          itemBuilder: (context, index) {
            final album = albums[index];
            return _ResultTile(
              leading: _Thumb(url: album.coverUrl, icon: Icons.album),
              title: album.title,
              subtitle: album.artistName,
              onTap: () {
                _remember();
                Navigator.push(context, MaterialPageRoute(builder: (_) => AlbumDetailScreen(album: album)));
              },
            );
          },
        );
      case SearchCategory.artists:
        final artists = _results.artists;
        return ListView.builder(
          itemCount: artists.length,
          itemBuilder: (context, index) {
            final artist = artists[index];
            return _ResultTile(
              leading: _Thumb(url: artist.pictureUrl, icon: Icons.person, circle: true),
              title: artist.name,
              subtitle: '아티스트',
              onTap: null,
            );
          },
        );
      case SearchCategory.playlists:
        final playlists = _results.playlists;
        return ListView.builder(
          itemCount: playlists.length,
          itemBuilder: (context, index) {
            final playlist = playlists[index];
            return _ResultTile(
              leading: PlaylistArtworkWidget(coverUrl: playlist.coverUrl, size: 48, borderRadius: 6),
              title: playlist.title,
              subtitle: playlist.numberOfTracks > 0 ? '${playlist.numberOfTracks}곡' : '플레이리스트',
              onTap: () {
                _remember();
                Navigator.push(context, MaterialPageRoute(builder: (_) => PlaylistDetailScreen(playlist: playlist)));
              },
            );
          },
        );
    }
  }
}

enum SearchCategory {
  tracks('트랙'),
  albums('앨범'),
  artists('아티스트'),
  playlists('플레이리스트');

  const SearchCategory(this.label);
  final String label;
}

class _ResultTile extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _ResultTile({required this.leading, required this.title, required this.subtitle, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.surfaceLight),
      ),
      child: ListTile(
        leading: leading,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        trailing: onTap == null ? null : const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        onTap: onTap,
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String url;
  final IconData icon;
  final bool circle;

  const _Thumb({required this.url, required this.icon, this.circle = false});

  @override
  Widget build(BuildContext context) {
    final fallback = SizedBox(width: 48, height: 48, child: Icon(icon, color: AppColors.cyanAccent));
    final image = url.isEmpty
        ? fallback
        : Image.network(url, width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback);
    return circle
        ? ClipOval(child: image)
        : ClipRRect(borderRadius: BorderRadius.circular(6), child: image);
  }
}
