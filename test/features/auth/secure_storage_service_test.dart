import 'package:flutter_test/flutter_test.dart';
import 'package:tidal_connect_lite/features/auth/domain/models/auth_token.dart';

void main() {
  test('AuthToken serialization and expiry check', () {
    final now = DateTime.now();
    final token = AuthToken(
      accessToken: 'access_123',
      refreshToken: 'refresh_456',
      expiresAt: now.add(const Duration(hours: 1)),
    );

    final json = token.toJson();
    final restored = AuthToken.fromJson(json);

    expect(restored.accessToken, 'access_123');
    expect(restored.refreshToken, 'refresh_456');
    expect(restored.isExpired, false);
  });

  test('AuthToken reports expired when past expiry', () {
    final expiredToken = AuthToken(
      accessToken: 'old',
      refreshToken: 'old_ref',
      expiresAt: DateTime.now().subtract(const Duration(minutes: 10)),
    );
    expect(expiredToken.isExpired, true);
  });
}
