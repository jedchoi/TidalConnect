import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/error_retry_view.dart';
import '../../../core/widgets/track_tile.dart';
import '../../tidal_api/data/tidal_api_client.dart';
import '../../tidal_api/domain/models/media_item.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  TidalApiClient get _apiClient => ref.read(apiClientProvider);
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const String _historyKey = 'search_history_list';
  List<String> _history = [];

  Timer? _debounce;
  bool _isSearching = false;
  List<MediaTrack> _searchTracks = [];
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
      final jsonStr = await _storage.read(key: _historyKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List list = jsonDecode(jsonStr);
        if (mounted) {
          setState(() {
            _history = list.map((e) => e.toString()).toList();
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _saveSearchHistory(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    _history.remove(trimmed);
    _history.insert(0, trimmed);
    if (_history.length > 15) {
      _history = _history.sublist(0, 15);
    }
    setState(() {});
    try {
      await _storage.write(key: _historyKey, value: jsonEncode(_history));
    } catch (_) {}
  }

  Future<void> _removeHistoryItem(String item) async {
    setState(() {
      _history.remove(item);
    });
    try {
      await _storage.write(key: _historyKey, value: jsonEncode(_history));
    } catch (_) {}
  }

  Future<void> _clearAllHistory() async {
    setState(() {
      _history.clear();
    });
    try {
      await _storage.delete(key: _historyKey);
    } catch (_) {}
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
    _saveSearchHistory(query);
    setState(() {
      _isSearching = true;
      _searchError = null;
    });
    try {
      final tracks = await _apiClient.searchTracks(query);
      if (mounted) {
        setState(() => _searchTracks = tracks);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _searchError = e is ApiFailure ? e.message : '검색하지 못했습니다.');
      }
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  void _searchWithQuery(String query) {
    _searchController.text = query;
    _performSearch(query);
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
              onSubmitted: (val) => _performSearch(val),
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
    if (_searchTracks.isEmpty) {
      return const Center(
        child: Text(
          '검색 결과가 없습니다',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return ListView.builder(
      itemCount: _searchTracks.length,
      itemBuilder: (context, index) {
        final track = _searchTracks[index];
        return TrackTile(track: track, queue: _searchTracks, index: index);
      },
    );
  }
}
