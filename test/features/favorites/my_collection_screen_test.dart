import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tidal_connect_lite/features/favorites/presentation/my_collection_screen.dart';

void main() {
  testWidgets('MyCollectionScreen displays headers', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: MyCollectionScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));

    expect(find.text('내 즐겨찾기'), findsOneWidget);
    expect(find.text('즐겨찾기 앨범'), findsOneWidget);
  });
}
