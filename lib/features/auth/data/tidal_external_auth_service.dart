import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/config/tidal_config.dart';
import '../../../core/utils/app_logger.dart';
import '../data/tidal_auth_repository.dart';
import '../data/tidal_pkce_auth.dart';
import '../domain/models/auth_token.dart';

class TidalExternalAuthService {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  Future<AuthToken?> startExternalLogin({
    required TidalAuthRepository authRepository,
  }) async {
    final completer = Completer<AuthToken?>();
    final codeVerifier = TidalPkceAuth.generateCodeVerifier();
    final codeChallenge = TidalPkceAuth.generateCodeChallenge(codeVerifier);
    final redirectUri = TidalConfig.redirectUri;

    // 1. Listen for deep link callback (tidalconnect://oauth-callback)
    _linkSubscription?.cancel();
    _linkSubscription = _appLinks.uriLinkStream.listen((Uri uri) async {
      AppLogger.log('TIDAL_AUTH', '외부 브라우저 리다이렉트 딥링크 수신: $uri', type: LogType.network);

      if (uri.scheme == 'tidalconnect' && uri.host == 'oauth-callback') {
        final authCode = uri.queryParameters['code'];
        if (authCode != null && authCode.isNotEmpty) {
          AppLogger.log('TIDAL_AUTH', 'TIDAL Authorization Code 획득 성공! Access Token 교환 시도중...', type: LogType.success);
          final token = await authRepository.exchangeAuthorizationCode(
            code: authCode,
            codeVerifier: codeVerifier,
            redirectUri: redirectUri,
          );
          _linkSubscription?.cancel();
          if (!completer.isCompleted) {
            completer.complete(token);
          }
        }
      }
    }, onError: (err) {
      AppLogger.log('TIDAL_AUTH', '딥링크 수신 예외 발생: $err', type: LogType.error);
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    });

    // 2. Build official OAuth Authorize URL
    final authUrl = Uri.parse('https://login.tidal.com/authorize').replace(queryParameters: {
      'client_id': TidalConfig.clientId,
      'response_type': 'code',
      'redirect_uri': redirectUri,
      'scope': 'r_usr',
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
    });

    AppLogger.log('TIDAL_AUTH', '외부 크롬 브라우저로 점프 실행: ${authUrl.toString()}', type: LogType.network);

    // 3. Launch external Chrome browser directly
    if (await canLaunchUrl(authUrl)) {
      await launchUrl(authUrl, mode: LaunchMode.externalApplication);
    } else {
      AppLogger.log('TIDAL_AUTH', '외부 브라우저를 띄울 수 없습니다.', type: LogType.error);
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    }

    // Timeout safety after 3 minutes if user closes browser
    Timer(const Duration(minutes: 3), () {
      if (!completer.isCompleted) {
        _linkSubscription?.cancel();
        completer.complete(null);
      }
    });

    return completer.future;
  }
}
