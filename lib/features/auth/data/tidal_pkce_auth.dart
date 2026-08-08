import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class TidalPkceAuth {
  /// Generates a cryptographically secure random PKCE code verifier
  static String generateCodeVerifier() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return base64UrlEncode(values).replaceAll('=', '').replaceAll('+', '-').replaceAll('/', '_');
  }

  /// Generates SHA-256 PKCE Code Challenge from verifier
  static String generateCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64UrlEncode(digest.bytes).replaceAll('=', '').replaceAll('+', '-').replaceAll('/', '_');
  }
}
