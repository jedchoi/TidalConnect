import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/tidal_api/data/tidal_api_client.dart';
import '../providers.dart';
import '../theme/app_colors.dart';

/// 즐겨찾기 하트 버튼. 로그인하지 않았으면 보이지 않는다.
class FavoriteButton extends ConsumerWidget {
  final FavoriteType type;
  final String id;
  final double size;

  const FavoriteButton({super.key, required this.type, required this.id, this.size = 22});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);
    if (!favorites.isAvailable || id.isEmpty) return const SizedBox.shrink();
    final isFavorite = favorites.isFavorite(type, id);
    return IconButton(
      iconSize: size,
      tooltip: isFavorite ? '즐겨찾기에서 삭제' : '즐겨찾기에 추가',
      icon: Icon(
        isFavorite ? Icons.favorite : Icons.favorite_border,
        color: isFavorite ? Colors.pinkAccent : AppColors.textSecondary,
      ),
      onPressed: favorites.isPending(type, id)
          ? null
          : () async {
              final messenger = ScaffoldMessenger.maybeOf(context);
              final ok = await favorites.toggle(type, id);
              if (!ok) {
                messenger?.showSnackBar(const SnackBar(content: Text('즐겨찾기를 바꾸지 못했습니다. 잠시 후 다시 시도해 주세요.')));
              }
            },
    );
  }
}
