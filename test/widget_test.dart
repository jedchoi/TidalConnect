import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tidal_connect_lite/features/main/presentation/main_screen.dart';
import 'package:tidal_connect_lite/features/main/presentation/splash_screen.dart';

import 'helpers/app_overrides.dart';

void main() {
  testWidgets('스플래시가 자동 로그인·스피커 탐색 후 메인 화면으로 넘어간다', (tester) async {
    final app = TestApp();
    await tester.pumpWidget(ProviderScope(
      overrides: app.overrides,
      child: const MaterialApp(home: SplashScreen()),
    ));

    expect(find.text('WAVECONNECT'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byType(MainScreen), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
    expect(app.ssdp.callCount, greaterThanOrEqualTo(1));
  });
}
