import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/data/tidal_auth_repository.dart';
import '../../auth/data/tidal_external_auth_service.dart';
import '../../auth/presentation/tidal_webview_login_modal.dart';
import '../../dlna/data/dlna_manager.dart';
import 'debug_log_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isAuthenticating = false;
  String _authStatusText = '로그인 필요 (Tidal 계정 미인증)';
  bool _isLoggedIn = false;

  final DlnaManager _dlnaManager = DlnaManager.instance;
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
          _authStatusText = 'Tidal 사용자 OAuth 로그인 완료';
        } else {
          _isLoggedIn = false;
          _authStatusText = '로그인 필요 (Tidal 계정 미인증)';
        }
      });
    }
  }

  Future<void> _handleTidalLogin() async {
    setState(() => _isAuthenticating = true);
    try {
      final externalAuthService = TidalExternalAuthService();
      final authToken = await externalAuthService.startExternalLogin(
        authRepository: _authRepo,
      );

      if (!mounted) return;

      if (authToken != null) {
        setState(() {
          _isLoggedIn = true;
          _authStatusText = 'Tidal 사용자 계정 로그인 완료!';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tidal 계정 로그인 성공! 이제 내 즐겨찾기 및 모든 음악을 가져올 수 있습니다.'),
            backgroundColor: AppColors.cyanAccent,
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
    final devices = await _dlnaManager.discoverDevices();
    if (!mounted) return;

    final remoteDevices = devices.where((d) => !d.isLocalSpeaker).toList();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          remoteDevices.isEmpty
              ? 'Wi-Fi 네트워크에서 발견된 DLNA 스피커가 없습니다. "실시간 네트워크 로그"에서 UDP 수신을 확인하세요.'
              : '${remoteDevices.length}개의 DLNA 스피커를 발견했습니다: ${remoteDevices.map((d) => "${d.friendlyName} (${d.locationUrl})").join(', ')}',
        ),
        backgroundColor: AppColors.surfaceCard,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('앱 설정', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.background,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report, color: AppColors.cyanAccent),
            tooltip: '실시간 디버그 로그',
            onPressed: () => DebugLogScreen.show(context),
          ),
        ],
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
                      _isLoggedIn ? '사용자 OAuth 인증 토큰 활성화됨' : '앱 내부에서 ID/PW만 입력하여 바로 로그인',
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
                          label: Text(_isLoggedIn ? '로그인 상태 재인증' : 'Tidal 계정 로그인'),
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
            'DLNA / UPnP 네트워크 스피커 목록',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.cyanAccent),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<bool>(
            valueListenable: _dlnaManager.isSearchingNotifier,
            builder: (context, isSearching, child) {
              return Card(
                color: AppColors.surfaceCard,
                child: ListTile(
                  leading: const Icon(Icons.speaker_group, color: AppColors.cyanAccent),
                  title: const Text('스피커 수동 재탐색', style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    isSearching ? 'SSDP M-SEARCH 멀티캐스트 전송 중...' : '실시간 Wi-Fi 네트워크 탐색',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  trailing: isSearching
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
              );
            },
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<List<dynamic>>(
            valueListenable: _dlnaManager.devicesNotifier,
            builder: (context, devices, child) {
              return Column(
                children: devices.map((device) {
                  final isSelected = device.udn == _dlnaManager.selectedDevice.udn;
                  return Card(
                    color: isSelected ? AppColors.cyanAccent.withOpacity(0.15) : AppColors.surfaceCard,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                        device.isLocalSpeaker ? Icons.phone_android : Icons.speaker,
                        color: isSelected ? AppColors.cyanAccent : Colors.white70,
                      ),
                      title: Text(
                        device.friendlyName,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        device.isLocalSpeaker ? '스마트폰 내장 스피커' : device.locationUrl,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle, color: AppColors.cyanAccent)
                          : OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.cyanAccent,
                                side: const BorderSide(color: AppColors.cyanAccent),
                              ),
                              onPressed: () {
                                setState(() {
                                  _dlnaManager.selectDevice(device);
                                });
                              },
                              child: const Text('선택'),
                            ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 24),
          const Text(
            '진단 및 디버그 디바이스 콘솔',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.cyanAccent),
          ),
          const SizedBox(height: 8),
          Card(
            color: AppColors.surfaceCard,
            child: ListTile(
              leading: const Icon(Icons.terminal, color: AppColors.cyanAccent),
              title: const Text('실시간 네트워크 / OAuth 로그 콘솔 열기', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: const Text('Tidal HTTP 응답 코드 및 SSDP UDP 패킷 로그를 눈으로 확인', style: TextStyle(color: AppColors.textSecondary)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white70),
              onTap: () => DebugLogScreen.show(context),
            ),
          ),
        ],
      ),
    );
  }
}
