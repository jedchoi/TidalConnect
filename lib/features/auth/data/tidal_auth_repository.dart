import '../domain/models/auth_token.dart';
import 'secure_storage_service.dart';

class TidalAuthRepository {
  final SecureStorageService _storageService;
  AuthToken? _currentToken;

  TidalAuthRepository({SecureStorageService? storageService})
      : _storageService = storageService ?? SecureStorageService();

  AuthToken? get currentToken => _currentToken;

  Future<AuthToken?> autoLogin() async {
    final token = await _storageService.getToken();
    if (token == null) {
      _currentToken = null;
      return null;
    }
    if (token.isExpired) {
      final refreshed = await refreshToken(token.refreshToken);
      _currentToken = refreshed;
      return refreshed;
    }
    _currentToken = token;
    return token;
  }

  Future<AuthToken?> refreshToken(String refreshToken) async {
    // In production, makes OAuth refresh call to Tidal API endpoint.
    // Stub implementation returning refreshed token instance.
    return null;
  }

  Future<void> saveToken(AuthToken token) async {
    _currentToken = token;
    await _storageService.saveToken(token);
  }

  Future<void> logout() async {
    _currentToken = null;
    await _storageService.deleteToken();
  }
}
