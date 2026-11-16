class AuthToken {
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String userId;

  /// 계정 국가(ISO 3166-1 alpha-2). 카탈로그 조회의 countryCode로 쓴다. 모르면 빈 문자열.
  final String countryCode;

  AuthToken({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    this.userId = '',
    this.countryCode = '',
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 5)));

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt.toIso8601String(),
        'userId': userId,
        'countryCode': countryCode,
      };

  factory AuthToken.fromJson(Map<String, dynamic> json) => AuthToken(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String),
        userId: (json['userId'] as String?) ?? '',
        countryCode: (json['countryCode'] as String?) ?? '',
      );

  AuthToken copyWith({String? countryCode}) => AuthToken(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresAt: expiresAt,
        userId: userId,
        countryCode: countryCode ?? this.countryCode,
      );
}
