import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../data/tidal_auth_repository.dart';
import '../domain/models/auth_token.dart';

class TidalDeviceLoginDialog extends StatefulWidget {
  final Map<String, dynamic> deviceAuthData;
  final TidalAuthRepository authRepository;

  const TidalDeviceLoginDialog({
    super.key,
    required this.deviceAuthData,
    required this.authRepository,
  });

  static Future<AuthToken?> show(
    BuildContext context, {
    required Map<String, dynamic> deviceAuthData,
    required TidalAuthRepository authRepository,
  }) {
    return showDialog<AuthToken>(
      context: context,
      barrierDismissible: false,
      builder: (context) => TidalDeviceLoginDialog(
        deviceAuthData: deviceAuthData,
        authRepository: authRepository,
      ),
    );
  }

  @override
  State<TidalDeviceLoginDialog> createState() => _TidalDeviceLoginDialogState();
}

class _TidalDeviceLoginDialogState extends State<TidalDeviceLoginDialog> {
  Timer? _pollingTimer;
  bool _isApproved = false;
  String _statusMessage = '사용자의 웹 브라우저 로그인 승인을 기다리는 중...';

  late final String _userCode;
  late final String _deviceCode;
  late final String _verificationUri;
  late final String _verificationUriComplete;
  late final int _interval;

  @override
  void initState() {
    super.initState();
    _userCode = widget.deviceAuthData['userCode'] as String? ?? '';
    _deviceCode = widget.deviceAuthData['deviceCode'] as String? ?? '';
    _verificationUri = widget.deviceAuthData['verificationUri'] as String? ?? 'link.tidal.com';
    _verificationUriComplete = widget.deviceAuthData['verificationUriComplete'] as String? ?? 'https://$_verificationUri';
    _interval = widget.deviceAuthData['interval'] as int? ?? 5;

    _startPolling();
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(Duration(seconds: _interval < 3 ? 3 : _interval), (timer) async {
      final token = await widget.authRepository.pollDeviceCodeToken(_deviceCode);
      if (token != null) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _isApproved = true;
            _statusMessage = 'Tidal 사용자 계정 인증 완료!';
          });
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) {
              Navigator.of(context).pop(token);
            }
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _openTidalAuthUrl() async {
    final uri = Uri.parse(_verificationUriComplete);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      final fallbackUri = Uri.parse('https://$_verificationUri');
      if (await canLaunchUrl(fallbackUri)) {
        await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.lock_open, color: AppColors.cyanAccent),
          SizedBox(width: 8),
          Text('Tidal 계정 인증 코드', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '아래 인증 코드를 확인하시고 버튼을 눌러 Tidal 웹페이지에서 승인해주세요.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.cyanAccent, width: 2),
            ),
            child: Text(
              _userCode,
              style: const TextStyle(
                color: AppColors.cyanAccent,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.cyanAccent,
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.open_in_browser),
            label: const Text('Tidal 웹 승인 페이지 열기', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: _openTidalAuthUrl,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _isApproved
                  ? const Icon(Icons.check_circle, color: Colors.greenAccent, size: 20)
                  : const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.cyanAccent),
                    ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _statusMessage,
                  style: TextStyle(
                    fontSize: 12,
                    color: _isApproved ? Colors.greenAccent : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('취소', style: TextStyle(color: Colors.white60)),
        ),
      ],
    );
  }
}
