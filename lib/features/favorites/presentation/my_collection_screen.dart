import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class MyCollectionScreen extends StatelessWidget {
  const MyCollectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('내 즐겨찾기', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text(
            '즐겨찾기 앨범',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.cyanAccent),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 140,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 5,
              itemBuilder: (context, index) => Container(
                width: 120,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Icon(Icons.album, color: Colors.white54, size: 48),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '내 플레이리스트',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.cyanAccent),
          ),
          const SizedBox(height: 12),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 3,
            itemBuilder: (context, index) => Card(
              color: AppColors.surfaceCard,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.playlist_play, color: AppColors.cyanAccent),
                title: Text('플레이리스트 ${index + 1}', style: const TextStyle(color: Colors.white)),
                subtitle: const Text('트랙 15개', style: TextStyle(color: AppColors.textSecondary)),
                trailing: const Icon(Icons.chevron_right, color: Colors.white54),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
