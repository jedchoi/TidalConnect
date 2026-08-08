import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/config/tidal_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_logger.dart';
import '../data/tidal_auth_repository.dart';
import '../data/tidal_pkce_auth.dart';
import '../domain/models/auth_token.dart';

class TidalWebLoginDialog extends StatefulWidget {
  final TidalAuthRepository authRepository;

  const TidalWebLoginDialog({
    super.key,
    required this.authRepository,
  });

  static Future<AuthToken?> show(
    BuildContext context, {
    required TidalAuthRepository authRepository,
  }) {
    return showDialog<AuthToken>(
      context: context,
      barrierDismissible: false,
      builder: (context) => TidalWebLoginDialog(authRepository: authRepository),
    );
  }

  @override
  State<TidalWebLoginDialog> createState() => _TidalWebLoginDialogState();
}

class _TidalWebLoginDialogState extends State<TidalWebLoginDialog> {
  final TextEditingController _codeController = TextEditingController();
  late final String _codeVerifier;
  late final String _codeChallenge;
  late final String _redirectUri;
  late final String _authUrl;

  bool _isExchanging = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _codeVerifier = TidalPkceAuth.generateCodeVerifier();
    _codeChallenge = TidalPkceAuth.generateCodeChallenge(_codeVerifier);
    _redirectUri = 'https://login.tidal.com/oauth2/callback';

    final uri = Uri.parse('https://login.tidal.com/authorize').replace(queryParameters: {
      'client_id': TidalConfig.clientId,
      'response_type': 'code',
      'redirect_uri': _redirectUri,
      'scope': 'r_usr w_usr',
      'code_challenge': _codeChallenge,
      'code_challenge_method': 'S256',
    });
    _authUrl = uri.toString();
  }

  Future<void> _openTidalWebPage() async {
    final uri = Uri.parse(_authUrl);
    AppLogger.log('TIDAL_AUTH', 'Tidal OAuth 웹 로그인 페이지 이동 시도: $_authUrl', type: LogType.network);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      AppLogger.log('TIDAL_AUTH', '브라우저 자동 실행 예외: $e (주소 복사 기능으로 대체)', type: LogType.warning);
      _copyUrlToClipboard();
    }
  }

  void _copyUrlToClipboard() {
    Clipboard.setData(ClipboardData(text: _authUrl));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidal 로그인 URL이 클립보드에 복사되었습니다! 웹 브라우저 주소창에 붙여넣으세요.'),
          backgroundColor: AppColors.cyanAccent,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _submitAuthorizationCode() async {
    var rawInput = _codeController.text.trim();
    if (rawInput.isEmpty) {
      setState(() => _errorMessage = '인증 코드 또는 리다이렉트 URL을 입력해주세요.');
      return;
    }

    // If full URL was pasted (e.g. https://login.tidal.com/oauth2/callback?code=XXXXX)
    String code = rawInput;
    if (rawInput.contains('code=')) {
      try {
        final parsedUri = Uri.parse(rawInput);
        code = parsedUri.queryParameters['code'] ?? rawInput;
      } catch (_) {}
    }

    setState(() {
      _isExchanging = true;
      _errorMessage = null;
    });

    final token = await widget.authRepository.exchangeAuthorizationCode(
      code: code,
      codeVerifier: _codeVerifier,
      redirectUri: _redirectUri,
    );

    if (!mounted) return;

    if (token != null) {
      Navigator.of(context).pop(token);
    } else {
      setState(() {
        _isExchanging = false;
        _errorMessage = '인증 코드가 유효하지 않거나 만료되었습니다. 다시 웹페이지를 열어 시도해주세요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.lock_person, color: AppColors.cyanAccent),
          SizedBox(width: 8),
          Text('Tidal 계정 공식 웹 로그인', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '1단계: 아래 버튼을 눌러 Tidal 웹페이지에서 로그인해주세요.',
              style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.cyanAccent,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.open_in_browser),
              label: const Text('1. Tidal 로그인 웹 브라우저 열기', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: _openTidalWebPage,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.cyanAccent,
                side: const BorderSide(color: AppColors.cyanAccent),
                minimumSize: const Size.fromHeight(40),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Tidal 로그인 URL 클립보드 복사'),
              onPressed: _copyUrlToClipboard,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white12),
              ),
              child: SelectableText(
                _authUrl,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '2단계: 로그인 후 브라우저 주소창의 URL(또는 code 값)을 아래에 붙여넣어주세요.',
              style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _codeController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'https://login.tidal.com/oauth2/callback?code=...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                filled: true,
                fillColor: Colors.black,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.cyanAccent),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.cyanAccent.withOpacity(0.5)),
                ),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: _isExchanging
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.check_circle_outline),
              label: const Text('2. 인증 완료 및 Access Token 발급', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: _isExchanging ? null : _submitAuthorizationCode,
            ),
          ],
        ),
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
