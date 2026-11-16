import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tidal_connect_lite/features/main/presentation/main_screen.dart';

import '../../helpers/app_overrides.dart';

void main() {
  testWidgets('MainScreen은 하단 탭 4개를 오간다', (tester) async {
    final app = TestApp();
    await tester.pumpWidget(ProviderScope(
      overrides: app.overrides,
      child: const MaterialApp(home: MainScreen()),
    ));
    await tester.pump();

    expect(find.text('내 즐겨찾기'), findsOneWidget);

    await tester.tap(find.text('추천'));
    await tester.pump();
    expect(find.text('추천 & 탐색'), findsOneWidget);
    expect(app.api.calls, contains('getFeaturedTracks'));

    await tester.tap(find.text('검색'));
    await tester.pump();
    expect(find.text('음악 검색'), findsOneWidget);

    await tester.tap(find.text('설정'));
    await tester.pump();
    expect(find.text('앱 설정'), findsOneWidget);

    await tester.tap(find.text('즐겨찾기'));
    await tester.pump();
    expect(find.text('내 즐겨찾기'), findsOneWidget);
  });
}
