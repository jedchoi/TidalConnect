import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tidal_connect_lite/features/player/presentation/mini_player_widget.dart';

void main() {
  testWidgets('MiniPlayerWidget renders controls and titles', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            bottomNavigationBar: MiniPlayerWidget(
              title: 'Test Tidal Song',
              artist: 'Test Artist Name',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Test Tidal Song'), findsOneWidget);
    expect(find.text('Test Artist Name'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.phone_android), findsOneWidget);
  });
}
