import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tidal_connect_lite/features/main/presentation/main_screen.dart';

void main() {
  testWidgets('MainScreen navigates between 4 tabs', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: MainScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('내 즐겨찾기'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.explore));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('추천 & 최근 재생'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.search));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('음악 검색'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('앱 설정'), findsOneWidget);
  });
}
