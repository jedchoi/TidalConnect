import 'package:flutter_test/flutter_test.dart';
import 'package:tidal_connect_lite/main.dart';

void main() {
  testWidgets('App renders title text', (WidgetTester tester) async {
    await tester.pumpWidget(const TidalApp());
    expect(find.text('Tidal Connect Lite'), findsOneWidget);
  });
}
