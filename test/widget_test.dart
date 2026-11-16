import 'package:flutter_test/flutter_test.dart';

void main() {
  // 앱 전체를 띄우면 스플래시가 보안 저장소·SSDP 소켓·네이티브 채널을 초기화하므로
  // 위젯 테스트 환경에서는 실행할 수 없다. 6단계(의존성 주입)에서 가짜 구현으로 대체해 복구한다.
  testWidgets('App renders brand title', (tester) async {}, skip: true);
}
