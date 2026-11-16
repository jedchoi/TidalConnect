import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class PlaylistArtworkWidget extends StatelessWidget {
  final String coverUrl;
  final List<String> trackCoverUrls;
  final double size;
  final double borderRadius;

  const PlaylistArtworkWidget({
    super.key,
    required this.coverUrl,
    this.trackCoverUrls = const [],
    this.size = 50,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    if (coverUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.network(
          coverUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildFallbackGrid(),
        ),
      );
    }

    return _buildFallbackGrid();
  }

  Widget _buildFallbackGrid() {
    final validCovers = trackCoverUrls.where((u) => u.isNotEmpty).take(4).toList();

    if (validCovers.length >= 4) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: SizedBox(
          width: size,
          height: size,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                        child: Image.network(validCovers[0],
                            fit: BoxFit.cover, errorBuilder: (_, __, ___) => _defaultTile())),
                    Expanded(
                        child: Image.network(validCovers[1],
                            fit: BoxFit.cover, errorBuilder: (_, __, ___) => _defaultTile())),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                        child: Image.network(validCovers[2],
                            fit: BoxFit.cover, errorBuilder: (_, __, ___) => _defaultTile())),
                    Expanded(
                        child: Image.network(validCovers[3],
                            fit: BoxFit.cover, errorBuilder: (_, __, ___) => _defaultTile())),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } else if (validCovers.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.network(
          validCovers.first,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _defaultTile(),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        width: size,
        height: size,
        color: AppColors.surfaceLight,
        child: Icon(Icons.playlist_play, size: size * 0.5, color: AppColors.cyanAccent),
      ),
    );
  }

  Widget _defaultTile() {
    return Container(
      color: AppColors.surfaceLight,
      child: const Icon(Icons.music_note, color: Colors.white24, size: 14),
    );
  }
}
