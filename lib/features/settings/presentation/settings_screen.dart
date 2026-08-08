import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/data/tidal_auth_repository.dart';
import '../../dlna/data/ssdp_discovery_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isSearching = false;
  bool _isAuthenticating = false;
  String _authStatusText = '로그인 필요 (Tidal OAuth 미인증)';
  bool _isLoggedIn = false;

  final SSDPDiscoveryService _ssdpService = SSDPDiscoveryService();
  final TidalAuthRepository _authRepo = TidalAuthRepository();

  @override
  void initState() {
    super.initState();
    _checkCurrentAuthStatus();
  }

  Future<void> _checkCurrentAuthStatus() async {
    final token = await _authRepo.autoLogin();
    if (mounted) {
      setState(() {
        if (token != null && !token.isExpired) {
          _isLoggedIn = true;
          _authStatusText = 'Tidal 계정 인증 완료 (OAuth 2.0 Token)';
        } else {
          _isLoggedIn = false;
          _authStatusText = '로그인 필요 (Tidal OAuth 미인증)';
        }
      });
    }
  }

  Future<void> _handleTidalLogin() async {
    setState(() => _isAuthenticating = true);
    try {
      final token = await _authRepo.authenticateClientCredentials();
      if (!mounted) return;

      if (token != null) {
        setState(() {
          _isLoggedIn = true;
          _authStatusText = 'Tidal Client ID/Secret OAuth 인증 성공!';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tidal OAuth 인증 성공! 액세스 토큰이 안전하게 저장되었습니다.'),
            backgroundColor: AppColors.cyanAccent,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tidal OAuth 인증 실패. Client Credentials를 확인하세요.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('인증 중 오류가 발생했습니다.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAuthenticating = false);
      }
    }
  }

  Future<void> _handleLogout() async {
    await _authRepo.logout();
    if (mounted) {
      setState(() {
        _isLoggedIn = false;
        _authStatusText = '로그아웃 완료';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그아웃 되었습니다.')),
      );
    }
  }

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
                ? 'Wi-Fi 네트워크에서 발견된 DLNA 스피커가 없습니다. 스피커의 Wi-Fi 연결을 확인하세요.'
                : '${remoteDevices.length}개의 DLNA 스피커를 발견했습니다: ${remoteDevices.map((d) => "${d.friendlyName} (${d.locationUrl})").join(', ')}',
          ),
          backgroundColor: AppColors.surfaceCard,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SSDP 네트워크 탐색 중 오류가 발생했습니다.'),
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
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.account_circle, color: AppColors.cyanAccent, size: 36),
                    title: Text(_authStatusText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      _isLoggedIn ? '자동 로그인 상태 유지 중' : '***REMOVED*** Client ID 적용됨',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.cyanAccent,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: _isAuthenticating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                )
                              : const Icon(Icons.login),
                          label: Text(_isLoggedIn ? 'OAuth 재인증' : 'Tidal 계정 로그인'),
                          onPressed: _isAuthenticating ? null : _handleTidalLogin,
                        ),
                      ),
                      if (_isLoggedIn) ...[
                        const SizedBox(width: 8),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                          ),
                          onPressed: _handleLogout,
                          child: const Text('로그아웃'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
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
                _isSearching ? 'SSDP M-SEARCH 멀티캐스트 전송 중...' : '실시간 Wi-Fi 네트워크 탐색',
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
