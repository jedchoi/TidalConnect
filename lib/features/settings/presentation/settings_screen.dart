import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('앱 설정', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text(
            'Tidal 계정 관리',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.cyanAccent),
          ),
          const SizedBox(height: 8),
          Card(
            color: AppColors.surfaceCard,
            child: const ListTile(
              leading: Icon(Icons.account_circle, color: AppColors.cyanAccent),
              title: Text('계정 상태: 로그인됨', style: TextStyle(color: Colors.white)),
              subtitle: Text('자동 로그인 활성화됨', style: TextStyle(color: AppColors.textSecondary)),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '오디오 음질 설정',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.cyanAccent),
          ),
          const SizedBox(height: 8),
          Card(
            color: AppColors.surfaceCard,
            child: const ListTile(
              leading: Icon(Icons.high_quality, color: AppColors.cyanAccent),
              title: Text('스트리밍 음질: LOSSLESS (FLAC 16-bit)', style: TextStyle(color: Colors.white)),
              trailing: Icon(Icons.arrow_drop_down, color: Colors.white54),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'DLNA / UPnP 네트워크',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.cyanAccent),
          ),
          const SizedBox(height: 8),
          Card(
            color: AppColors.surfaceCard,
            child: ListTile(
              leading: const Icon(Icons.speaker_group, color: AppColors.cyanAccent),
              title: const Text('스피커 수동 재탐색', style: TextStyle(color: Colors.white)),
              subtitle: const Text('SSDP M-SEARCH 패킷 전송', style: TextStyle(color: AppColors.textSecondary)),
              trailing: IconButton(
                icon: const Icon(Icons.refresh, color: AppColors.cyanAccent),
                onPressed: () {},
              ),
            ),
          ),
        ],
      ),
    );
  }
}
