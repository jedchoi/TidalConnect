import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../dlna/data/ssdp_discovery_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isSearching = false;
  final SSDPDiscoveryService _ssdpService = SSDPDiscoveryService();

  Future<void> _runDeviceDiscovery() async {
    setState(() => _isSearching = true);
    try {
      final devices = await _ssdpService.discoverDevices();
      if (!mounted) return;
      
      final remoteDevices = devices.where((d) => !d.isLocalSpeaker).toList();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            remoteDevices.isEmpty
                ? '동일 Wi-Fi 네트워크에서 DLNA 스피커를 찾지 못했습니다.'
                : '${remoteDevices.length}개의 DLNA 스피커를 새로 발견했습니다: ${remoteDevices.map((d) => d.friendlyName).join(', ')}',
          ),
          backgroundColor: AppColors.surfaceCard,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SSDP 네트워크 검색 중 오류가 발생했습니다.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

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
              title: Text('계정 상태: OAuth 로그인 필요 (Mock UI 모드)', style: TextStyle(color: Colors.white)),
              subtitle: Text('Tidal Developer Client ID 설정 시 영구 자동 로그인 연동 가능', style: TextStyle(color: AppColors.textSecondary)),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '오디오 스트리밍 음질 설정',
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
              subtitle: Text(
                _isSearching ? 'SSDP M-SEARCH 패킷 전송 중...' : '실시간 Wi-Fi 네트워크 탐색',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              trailing: _isSearching
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.cyanAccent),
                    )
                  : IconButton(
                      icon: const Icon(Icons.refresh, color: AppColors.cyanAccent),
                      onPressed: _runDeviceDiscovery,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
