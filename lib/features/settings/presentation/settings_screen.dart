import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../data/playback_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/data/tidal_auth_repository.dart';
import '../../auth/presentation/tidal_webview_login_modal.dart';
import '../../dlna/data/dlna_manager.dart';
import 'debug_log_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _isAuthenticating = false;

  DlnaManager get _dlnaManager => ref.read(dlnaManagerProvider);
  TidalAuthRepository get _authRepo => ref.read(authRepositoryProvider);

  Future<void> _handleTidalLogin() async {
    setState(() => _isAuthenticating = true);
    try {
      final authToken = await TidalWebViewLoginModal.show(
        context,
        authRepository: _authRepo,
      );

      if (!mounted) return;

      if (authToken != null) {
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
    // 순서: 재생 정지 -> 네이티브 자격 증명·저장 토큰 삭제(logout 내부) -> Provider로 상태 전파
    ref.read(playerManagerProvider).stop();
    await _authRepo.logout();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그아웃 되었습니다.')),
      );
    }
  }

  Future<void> _runDeviceDiscovery() async {
    // 설정 화면의 ValueListenableBuilder가 실시간으로 목록을 갱신하므로 불필요한 UI 모달이나 SnackBar를 띄우지 않습니다.
    await _dlnaManager.discoverDevices();
  }

  @override
  Widget build(BuildContext context) {
    // 로그인 표시는 인증 저장소의 사용자 토큰만 따른다(앱 토큰은 로그인으로 보지 않는다).
    final isLoggedIn = ref.watch(loggedInUserIdProvider) != null;
    final authStatusText = isLoggedIn ? 'Tidal 사용자 OAuth 로그인 완료' : '로그인 필요 (Tidal 계정 미인증)';

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
                    title: Text(authStatusText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      isLoggedIn ? '사용자 OAuth 인증 토큰 활성화됨' : '앱 내부에서 ID/PW만 입력하여 바로 로그인',
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
                          label: Text(isLoggedIn ? '로그인 상태 재인증' : 'Tidal 계정 로그인'),
                          onPressed: _isAuthenticating ? null : _handleTidalLogin,
                        ),
                      ),
                      if (isLoggedIn) ...[
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
            '스트리밍 음질',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.cyanAccent),
          ),
          const SizedBox(height: 8),
          const _AudioQualityCard(),
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
                      : const Icon(Icons.refresh, color: AppColors.cyanAccent),
                  onTap: isSearching ? null : _runDeviceDiscovery,
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: Listenable.merge([_dlnaManager.devicesNotifier, _dlnaManager.selectedDeviceNotifier]),
            builder: (context, child) {
              final devices = _dlnaManager.devices;
              return Column(
                children: devices.map((device) {
                  final isSelected = device.udn == _dlnaManager.selectedDevice.udn;
                  return Card(
                    color: isSelected ? AppColors.cyanAccent.withValues(alpha: 0.15) : AppColors.surfaceCard,
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
                                // 재생 중이면 새 기기로 이어서 재생하도록 PlayerManager를 거친다.
                                ref.read(playerManagerProvider).switchPlaybackDevice(device);
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

/// 음질 선택. 고른 값은 저장되고 다음 곡부터 폰·스피커 재생에 모두 적용된다.
class _AudioQualityCard extends ConsumerWidget {
  const _AudioQualityCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.read(playbackSettingsProvider);
    return Card(
      color: AppColors.surfaceCard,
      child: ValueListenableBuilder<AudioQualityOption>(
        valueListenable: settings.audioQuality,
        builder: (context, selected, _) => RadioGroup<AudioQualityOption>(
          groupValue: selected,
          onChanged: (value) {
            if (value != null) settings.setAudioQuality(value);
          },
          child: Column(
          children: [
            for (final option in AudioQualityOption.values)
              RadioListTile<AudioQualityOption>(
                value: option,
                activeColor: AppColors.cyanAccent,
                title: Text(option.label, style: const TextStyle(color: Colors.white)),
                subtitle: Text(option.detail, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                selected == AudioQualityOption.hiRes
                    ? 'DLNA 스피커에서 Hi-Res는 DASH 스트림을 이어 붙여 보내므로 재생 위치를 옮길 수 없습니다. '
                        '변경한 음질은 다음 곡부터 적용됩니다.'
                    : '변경한 음질은 다음 곡부터 적용됩니다.',
                style: TextStyle(
                  color: selected == AudioQualityOption.hiRes ? Colors.amberAccent : AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}
