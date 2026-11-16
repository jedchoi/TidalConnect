import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/auth/data/tidal_auth_repository.dart';
import '../features/auth/domain/models/auth_token.dart';

/// 앱 전체에서 하나만 쓰는 인증 저장소.
final authRepositoryProvider = Provider<TidalAuthRepository>((ref) => TidalAuthRepository());

/// 로그인 상태. 사용자 토큰이 바뀔 때마다 구독 중인 위젯을 다시 그린다.
final authStateProvider = ChangeNotifierProvider<ValueNotifier<AuthToken?>>(
  (ref) => ref.watch(authRepositoryProvider).userToken,
);

/// 로그인한 사용자 ID. 로그아웃 상태면 null.
/// 토큰 갱신처럼 ID가 그대로인 변경에는 반응하지 않는다.
final loggedInUserIdProvider = Provider<String?>((ref) => ref.watch(authStateProvider).value?.userId);
