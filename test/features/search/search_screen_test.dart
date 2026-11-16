import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tidal_connect_lite/features/search/data/search_history_store.dart';
import 'package:tidal_connect_lite/features/search/presentation/search_screen.dart';
import 'package:tidal_connect_lite/features/tidal_api/domain/models/media_item.dart';

import '../../helpers/app_overrides.dart';

void main() {
  testWidgets('입력 중에는 기록하지 않고 제출하면 기록·결과 칩을 보여준다', (tester) async {
    final app = TestApp();
    app.api.tracks = [
      MediaTrack(id: '1', title: 'Hello', artistName: 'A', albumTitle: 'B', coverUrl: '', durationSeconds: 60),
    ];
    await tester.pumpWidget(ProviderScope(
      overrides: app.overrides,
      child: const MaterialApp(home: SearchScreen()),
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'hel');
    await tester.pump(const Duration(milliseconds: 600));
    expect(app.api.calls, contains('searchAll:hel'));
    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(SearchHistoryStore.key), isNull);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(SearchHistoryStore.key), ['hello']);
    expect(find.text('트랙 1'), findsOneWidget);
    expect(find.text('Hello'), findsOneWidget);

    await tester.tap(find.text('앨범 0'));
    await tester.pump();
    expect(find.text('앨범 결과가 없습니다'), findsOneWidget);
  });
}
