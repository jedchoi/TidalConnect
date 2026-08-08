class AuthToken {
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String userId;

  AuthToken({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    this.userId = '',
  });

  bool get isExpired =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 5)));

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt.toIso8601String(),
        'userId': userId,
      };

  factory AuthToken.fromJson(Map<String, dynamic> json) => AuthToken(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String),
        userId: (json['userId'] as String?) ?? '',
      );
}
