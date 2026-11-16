import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_logger.dart';

class DebugLogScreen extends StatelessWidget {
  const DebugLogScreen({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => const SizedBox(
        height: 600,
        child: DebugLogScreen(),
      ),
    );
  }

  Color _getLogColor(LogType type) {
    switch (type) {
      case LogType.success:
        return Colors.greenAccent;
      case LogType.error:
        return Colors.redAccent;
      case LogType.warning:
        return Colors.amberAccent;
      case LogType.network:
        return AppColors.cyanAccent;
      case LogType.info:
      default:
        return Colors.white70;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('실시간 네트워크 / OAuth 로그', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.surfaceCard,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white70),
            onPressed: () => AppLogger.clear(),
          ),
        ],
      ),
      body: ValueListenableBuilder<List<LogEntry>>(
        valueListenable: AppLogger.logsNotifier,
        builder: (context, logs, child) {
          if (logs.isEmpty) {
            return const Center(
              child: Text('기록된 로그가 없습니다', style: TextStyle(color: AppColors.textSecondary)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12.0),
            itemCount: logs.length,
            separatorBuilder: (context, index) => const Divider(color: Colors.white12, height: 1),
            itemBuilder: (context, index) {
              final entry = logs[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '[${entry.formattedTime}]',
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontFamily: 'monospace'),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getLogColor(entry.type).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: _getLogColor(entry.type).withValues(alpha: 0.5)),
                          ),
                          child: Text(
                            entry.tag,
                            style:
                                TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _getLogColor(entry.type)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.message,
                      style: const TextStyle(fontSize: 12, color: Colors.white, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
