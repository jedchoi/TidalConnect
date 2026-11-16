/// TIDAL 클라이언트 설정.
///
/// 키는 소스에 두지 않고 빌드할 때 주입한다.
///   flutter run --dart-define-from-file=config/tidal.json
/// `config/tidal.json`은 git에서 제외되며, 형식은 `config/tidal.example.json`을 참고한다.
class TidalConfig {
  static const String clientId = String.fromEnvironment('TIDAL_CLIENT_ID');
  static const String clientSecret = String.fromEnvironment('TIDAL_CLIENT_SECRET');
  static const String redirectUri = String.fromEnvironment(
    'TIDAL_REDIRECT_URI',
    defaultValue: 'https://tidal.com/android/login/auth',
  );

  static const String authBaseUrl = 'https://auth.tidal.com/v1/oauth2';
  static const String apiBaseUrl = 'https://api.tidal.com/v1';

  static bool get isConfigured => clientId.isNotEmpty && clientSecret.isNotEmpty;
}
