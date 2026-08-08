import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tidal_connect_lite/main.dart';

void main() {
  testWidgets('App renders title text', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: TidalConnectLiteApp(),
      ),
    );

    expect(find.textContaining('Tidal Connect Lite'), findsWidgets);
  });
}
