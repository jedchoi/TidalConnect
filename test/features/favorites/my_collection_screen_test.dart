import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tidal_connect_lite/features/favorites/presentation/my_collection_screen.dart';

import '../../helpers/app_overrides.dart';

void main() {
  testWidgets('MyCollectionScreen displays app bar title', (WidgetTester tester) async {
    final app = TestApp();
    await tester.pumpWidget(
      ProviderScope(
        overrides: app.overrides,
        child: const MaterialApp(
          home: MyCollectionScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('내 즐겨찾기'), findsOneWidget);
  });
}
