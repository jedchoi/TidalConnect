import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../utils/paginator.dart';

/// 목록 끝의 '더 불러오는 중' 표시. 실패했거나 [asButton]이면 누르는 버튼으로 보여준다.
class LoadMoreIndicator extends StatelessWidget {
  final Paginator<Object?> paginator;
  final bool asButton;

  /// 가로 목록에서 쓸 때의 폭. null이면 가로로 꽉 채운다.
  final double? width;

  const LoadMoreIndicator({super.key, required this.paginator, this.asButton = false, this.width});

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (paginator.isLoadingMore) {
      child = const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.cyanAccent),
      );
    } else if (paginator.loadMoreFailed || asButton) {
      child = TextButton.icon(
        onPressed: paginator.loadMore,
        icon: Icon(paginator.loadMoreFailed ? Icons.refresh : Icons.expand_more, color: AppColors.cyanAccent),
        label: Text(
          paginator.loadMoreFailed ? '다시 시도' : '더 보기',
          style: const TextStyle(color: AppColors.cyanAccent),
        ),
      );
    } else {
      child = const SizedBox(height: 24);
    }
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(child: child),
      ),
    );
  }
}
