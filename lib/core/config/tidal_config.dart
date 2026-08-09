class TidalConfig {
  // [기존 Developer Dashboard 키 - 주석 보관]
  // static const String clientId = '***REMOVED***';
  // static const String clientSecret = '***REMOVED***';
  // static const String redirectUri = 'tidalconnect://oauth-callback';

  // [공식 TIDAL Android PKCE 클라이언트 키 & 공식 Redirect URI]
  static const String clientId = '***REMOVED***';
  static const String clientSecret = '***REMOVED***';
  static const String redirectUri = 'https://tidal.com/android/login/auth';

  static const String authBaseUrl = 'https://auth.tidal.com/v1/oauth2';
  static const String apiBaseUrl = 'https://api.tidal.com/v1';
}
