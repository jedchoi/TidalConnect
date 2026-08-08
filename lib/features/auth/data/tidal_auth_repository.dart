import '../domain/models/auth_token.dart';
import 'secure_storage_service.dart';

class TidalAuthRepository {
  final SecureStorageService _storageService;

  TidalAuthRepository({SecureStorageService? storageService})
      : _storageService = storageService ?? SecureStorageService();

  Future<AuthToken?> autoLogin() async {
    final token = await _storageService.getToken();
    if (token == null) return null;
    if (token.isExpired) {
      // Token expired, attempt refresh
      return await refreshToken(token.refreshToken);
    }
    return token;
  }

  Future<AuthToken?> refreshToken(String refreshToken) async {
    // In production, makes OAuth refresh call to Tidal API endpoint.
    // Stub implementation returning refreshed token instance.
    return null;
  }

  Future<void> saveToken(AuthToken token) async {
    await _storageService.saveToken(token);
  }

  Future<void> logout() async {
    await _storageService.deleteToken();
  }
}
