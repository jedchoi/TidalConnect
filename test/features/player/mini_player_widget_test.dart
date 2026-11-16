import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tidal_connect_lite/features/player/presentation/mini_player_widget.dart';

import '../../helpers/app_overrides.dart';

void main() {
  testWidgets('MiniPlayerWidget renders placeholder title and controls', (WidgetTester tester) async {
    final app = TestApp();
    await tester.pumpWidget(
      ProviderScope(
        overrides: app.overrides,
        child: const MaterialApp(
          home: Scaffold(
            bottomNavigationBar: MiniPlayerWidget(autoStartDiscovery: false),
          ),
        ),
      ),
    );

    expect(find.text('Tidal 음원 선택 안됨'), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);
    expect(find.byIcon(Icons.phone_android), findsWidgets);
  });
}
