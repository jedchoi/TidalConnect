import 'package:flutter/material.dart';
import '../../features/tidal_api/domain/models/media_item.dart';
import '../theme/app_colors.dart';

/// 트랙 목록의 작은 음질 배지(MAX, ATMOS, FLAC, HIGH, LOW).
class QualityBadge extends StatelessWidget {
  final MediaTrack track;
  const QualityBadge({super.key, required this.track});

  @override
  Widget build(BuildContext context) {
    final highlight = track.isMax;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: highlight ? Colors.amber.withValues(alpha: 0.2) : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        track.qualityBadgeText,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: highlight ? Colors.amberAccent : AppColors.cyanAccent,
        ),
      ),
    );
  }
}
