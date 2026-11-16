import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/tidal_api/domain/models/media_item.dart';
import '../providers.dart';
import '../theme/app_colors.dart';
import '../utils/format.dart';
import 'quality_badge.dart';

/// 트랙 목록의 한 행. 현재 곡 강조와 재생·일시정지 아이콘을 재생 상태에 맞춰 갱신한다.
///
/// 누르면 [queue]를 대기열로 삼아 [index]번째 곡부터 재생한다.
class TrackTile extends ConsumerWidget {
  final MediaTrack track;
  final List<MediaTrack> queue;
  final int index;

  /// 왼쪽 영역. 지정하지 않으면 앨범 커버를 보여준다. 인자는 현재 재생 중인 곡인지 여부.
  final Widget Function(bool isCurrent)? leadingBuilder;

  /// 아래 줄. 지정하지 않으면 "아티스트 • 앨범".
  final String? subtitle;
  final bool showDuration;
  final EdgeInsetsGeometry margin;

  const TrackTile({
    super.key,
    required this.track,
    required this.queue,
    required this.index,
    this.leadingBuilder,
    this.subtitle,
    this.showDuration = false,
    this.margin = const EdgeInsets.only(bottom: 8),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.read(playerManagerProvider);
    return ListenableBuilder(
      listenable: Listenable.merge([player.currentTrackNotifier, player.isPlayingNotifier]),
      builder: (context, _) {
        final isCurrent = player.currentTrack?.id == track.id;
        final isPlayingThis = isCurrent && player.isPlaying;

        void play() => player.playTrack(track, queue: queue, index: index);

        return Container(
          margin: margin,
          decoration: BoxDecoration(
            color: isCurrent ? AppColors.cyanAccent.withValues(alpha: 0.1) : AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isCurrent ? AppColors.cyanAccent : AppColors.surfaceLight),
          ),
          child: ListTile(
            leading: leadingBuilder?.call(isCurrent) ?? _Cover(url: track.coverUrl),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isCurrent ? AppColors.cyanAccent : Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                QualityBadge(track: track),
              ],
            ),
            subtitle: Text(
              subtitle ?? '${track.artistName} • ${track.albumTitle}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showDuration)
                  Text(
                    formatDuration(track.durationSeconds),
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                IconButton(
                  icon: Icon(
                    isPlayingThis ? Icons.pause_circle_filled : Icons.play_circle_fill,
                    color: AppColors.cyanAccent,
                  ),
                  tooltip: isPlayingThis ? '일시정지' : '재생',
                  onPressed: isCurrent ? player.togglePlayPause : play,
                ),
              ],
            ),
            onTap: isCurrent ? null : play,
          ),
        );
      },
    );
  }
}

class _Cover extends StatelessWidget {
  final String url;
  const _Cover({required this.url});

  @override
  Widget build(BuildContext context) {
    const fallback = SizedBox(width: 44, height: 44, child: Icon(Icons.music_note, color: AppColors.cyanAccent));
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: url.isEmpty
          ? fallback
          : Image.network(url, width: 44, height: 44, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback),
    );
  }
}
