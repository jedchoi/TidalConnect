import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../../../core/config/tidal_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_logger.dart';
import '../data/tidal_auth_repository.dart';
import '../data/tidal_pkce_auth.dart';
import '../domain/models/auth_token.dart';

class TidalWebViewLoginModal extends StatefulWidget {
  final TidalAuthRepository authRepository;

  const TidalWebViewLoginModal({
    super.key,
    required this.authRepository,
  });

  static Future<AuthToken?> show(
    BuildContext context, {
    required TidalAuthRepository authRepository,
  }) {
    return showModalBottomSheet<AuthToken>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: TidalWebViewLoginModal(authRepository: authRepository),
      ),
    );
  }

  @override
  State<TidalWebViewLoginModal> createState() => _TidalWebViewLoginModalState();
}

class _TidalWebViewLoginModalState extends State<TidalWebViewLoginModal> {
  late final WebViewController _controller;
  late final String _codeVerifier;
  late final String _codeChallenge;
  late final Uri _authUri;
  final String _redirectUri = TidalConfig.redirectUri;

  bool _isLoadingPage = true;
  bool _isExchangingToken = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _codeVerifier = TidalPkceAuth.generateCodeVerifier();
    _codeChallenge = TidalPkceAuth.generateCodeChallenge(_codeVerifier);

    _authUri = Uri.parse('https://login.tidal.com/authorize').replace(queryParameters: {
      'client_id': TidalConfig.clientId,
      'response_type': 'code',
      'redirect_uri': _redirectUri,
      'scope': 'r_usr w_usr',
      'code_challenge': _codeChallenge,
      'code_challenge_method': 'S256',
    });

    AppLogger.log('TIDAL_AUTH', 'In-App WebView Tidal PKCE 로그인 시작', type: LogType.network);

    _controller = WebViewController()
      ..setUserAgent("Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36")
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (mounted) setState(() => _isLoadingPage = true);
            _checkInterceptUrl(url);
          },
          onPageFinished: (String url) {
            if (mounted) setState(() => _isLoadingPage = false);
            _checkInterceptUrl(url);
          },
          onUrlChange: (UrlChange change) {
            if (change.url != null) {
              _checkInterceptUrl(change.url!);
            }
          },
          onWebResourceError: (WebResourceError error) {
            if (error.url != null) {
              _checkInterceptUrl(error.url!);
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            if (_checkInterceptUrl(request.url)) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

    if (_controller.platform is AndroidWebViewController) {
      final androidController = _controller.platform as AndroidWebViewController;
      androidController.setMediaPlaybackRequiresUserGesture(false);
    }

    _controller.loadRequest(_authUri);
  }

  bool _checkInterceptUrl(String url) {
    if (_isExchangingToken) return true;

    if (url.startsWith(_redirectUri) || url.startsWith('tidalconnect://') || url.contains('code=')) {
      try {
        final parsedUri = Uri.parse(url);
        final code = parsedUri.queryParameters['code'];
        if (code != null && code.isNotEmpty) {
          _handleAuthorizationCode(code);
          return true;
        }
      } catch (e) {
        AppLogger.log('TIDAL_AUTH', 'Redirect DeepLink 파싱 에러: $e', type: LogType.error);
      }
    }
    return false;
  }

  Future<void> _handleAuthorizationCode(String code) async {
    if (_isExchangingToken) return;
    setState(() {
      _isExchangingToken = true;
    });

    AppLogger.log('TIDAL_AUTH', 'TIDAL 인증 코드 수신 -> 토큰 교환 시도', type: LogType.success);

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
        _isExchangingToken = false;
        _errorMessage = '인증 토큰 교환 실패. Tidal 개발자 대시보드에 $_redirectUri 주소가 등록되어 있는지 확인해주세요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Tidal 계정 공식 로그인', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.surfaceCard,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(null),
        ),
        bottom: _isLoadingPage || _isExchangingToken
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(color: AppColors.cyanAccent, backgroundColor: Colors.transparent),
              )
            : null,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isExchangingToken)
            Container(
              color: Colors.black87,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.cyanAccent),
                    SizedBox(height: 16),
                    Text(
                      'TIDAL Authorization Code 획득 성공!',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Tidal Access Token을 안전하게 발급받는 중입니다...',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          if (_errorMessage != null)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
