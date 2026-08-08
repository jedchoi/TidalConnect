import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('추천 & 최근 재생', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text(
            '최근 재생한 음악',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.cyanAccent),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 4,
              itemBuilder: (context, index) => Container(
                width: 100,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Icon(Icons.history, color: Colors.white54, size: 36),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Tidal 추천 믹스',
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
                leading: const Icon(Icons.auto_awesome, color: AppColors.cyanAccent),
                title: Text('My Daily Mix ${index + 1}', style: const TextStyle(color: Colors.white)),
                subtitle: const Text('Tidal 추천 음원 기반', style: TextStyle(color: AppColors.textSecondary)),
                trailing: const Icon(Icons.play_circle_fill, color: AppColors.cyanAccent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
