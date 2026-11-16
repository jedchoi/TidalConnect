import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../tidal_api/domain/models/media_item.dart';

/// 추천 탭 맨 위의 '최근 재생' 가로 목록. 기록이 없으면 아무것도 그리지 않는다.
class RecentlyPlayedSection extends ConsumerWidget {
  const RecentlyPlayedSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.read(recentlyPlayedProvider);
    final player = ref.read(playerManagerProvider);
    return ValueListenableBuilder<List<MediaTrack>>(
      valueListenable: store.tracks,
      builder: (context, tracks, _) {
        if (tracks.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '최근 재생',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                TextButton(
                  onPressed: store.clear,
                  child: const Text('지우기', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 160,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: tracks.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  // 목록 순서가 재생할 때마다 바뀌므로 누른 시점의 목록을 대기열로 고정한다.
                  return _RecentCard(
                    track: track,
                    onTap: () => player.playTrack(track, queue: List.of(tracks), index: index),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

class _RecentCard extends StatelessWidget {
  final MediaTrack track;
  final VoidCallback onTap;
  const _RecentCard({required this.track, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: 110,
      height: 110,
      color: Colors.white10,
      child: const Icon(Icons.music_note, color: AppColors.cyanAccent, size: 36),
    );
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 110,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: track.coverUrl.isEmpty
                  ? fallback
                  : Image.network(
                      track.coverUrl,
                      width: 110,
                      height: 110,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => fallback,
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
            ),
            Text(
              track.artistName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
