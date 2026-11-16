import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/paginator.dart';
import '../../../core/widgets/error_retry_view.dart';
import '../../../core/widgets/load_more_indicator.dart';
import '../../../core/widgets/track_tile.dart';
import '../../favorites/presentation/album_detail_screen.dart';
import '../../player/presentation/mini_player_widget.dart';
import '../../tidal_api/data/tidal_api_client.dart';
import '../../tidal_api/domain/models/media_item.dart';

/// 아티스트 화면. 인기 트랙과 앨범을 보여준다.
class ArtistDetailScreen extends ConsumerStatefulWidget {
  final MediaArtist artist;

  const ArtistDetailScreen({super.key, required this.artist});

  @override
  ConsumerState<ArtistDetailScreen> createState() => _ArtistDetailScreenState();
}

class _ArtistDetailScreenState extends ConsumerState<ArtistDetailScreen> {
  static const int _topTrackCount = 10;

  TidalApiClient get _apiClient => ref.read(apiClientProvider);

  bool _isLoading = true;
  String? _errorMessage;
  List<MediaTrack> _topTracks = const [];
  late final Paginator<MediaAlbum> _albums =
      Paginator((offset) => _apiClient.getArtistAlbums(widget.artist.id, offset: offset));

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _albums.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final results = await Future.wait([
        _apiClient.getArtistTopTracks(widget.artist.id, limit: _topTrackCount),
        _albums.refresh(),
      ]);
      if (!mounted) return;
      setState(() {
        _topTracks = results[0] as List<MediaTrack>;
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.log('ARTIST', '아티스트 정보 로딩 오류: $e', type: LogType.error);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e is ApiFailure ? e.message : '아티스트 정보를 불러오지 못했습니다.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.artist.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.surfaceCard,
        elevation: 0,
      ),
      bottomNavigationBar: const MiniPlayerWidget(autoStartDiscovery: false, useSafeArea: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.cyanAccent))
          : _errorMessage != null
              ? ErrorRetryView(message: _errorMessage!, onRetry: _load)
              : ListenableBuilder(
                  listenable: _albums,
                  builder: (context, _) => NotificationListener<ScrollNotification>(
                    onNotification: _albums.onScroll,
                    child: CustomScrollView(slivers: _buildSlivers()),
                  ),
                ),
    );
  }

  List<Widget> _buildSlivers() {
    final albums = _albums.items;
    return [
      SliverToBoxAdapter(child: _Header(artist: widget.artist)),
      if (_topTracks.isNotEmpty) ...[
        const SliverToBoxAdapter(child: _SectionTitle('인기 트랙')),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => TrackTile(
              track: _topTracks[index],
              queue: _topTracks,
              index: index,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            ),
            childCount: _topTracks.length,
          ),
        ),
      ],
      if (albums.isNotEmpty) ...[
        SliverToBoxAdapter(child: _SectionTitle('앨범', trailing: '${_albums.totalCount}개')),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.78,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _AlbumCard(album: albums[index]),
              childCount: albums.length,
            ),
          ),
        ),
        if (_albums.hasMore) SliverToBoxAdapter(child: LoadMoreIndicator(paginator: _albums)),
      ],
      if (_topTracks.isEmpty && albums.isEmpty)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: Text('표시할 곡이 없습니다', style: TextStyle(color: AppColors.textSecondary))),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: 80)),
    ];
  }
}

class _Header extends StatelessWidget {
  final MediaArtist artist;
  const _Header({required this.artist});

  @override
  Widget build(BuildContext context) {
    const fallback = CircleAvatar(
      radius: 64,
      backgroundColor: AppColors.surfaceLight,
      child: Icon(Icons.person, size: 64, color: AppColors.cyanAccent),
    );
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          artist.pictureUrl.isEmpty
              ? fallback
              : ClipOval(
                  child: Image.network(
                    artist.pictureUrl,
                    width: 128,
                    height: 128,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => fallback,
                  ),
                ),
          const SizedBox(height: 12),
          Text(
            artist.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? trailing;
  const _SectionTitle(this.title, {this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          if (trailing != null) Text(trailing!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  final MediaAlbum album;
  const _AlbumCard({required this.album});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: Colors.white10,
      child: const Center(child: Icon(Icons.album, size: 40, color: AppColors.cyanAccent)),
    );
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AlbumDetailScreen(album: album))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: album.coverUrl.isEmpty
                  ? fallback
                  : Image.network(album.coverUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            album.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
          ),
          if (album.qualityLabel.isNotEmpty)
            Text(album.qualityLabel, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}
