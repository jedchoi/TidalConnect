import 'dart:io';

import 'package:kiri_check/kiri_check.dart';

/// 속성 기반 테스트의 고정 seed. 로컬과 CI가 매번 같은 입력으로 실행한다.
const defaultPbtSeed = 20261117;

/// 속성 하나가 시도하는 입력 수.
const pbtExamples = 100;

/// 속성 기반 테스트 설정. 속성 테스트가 있는 파일의 `main()` 첫머리에서 부른다.
///
/// seed는 환경 변수 `PBT_SEED`가 정수면 그 값, 아니면 [defaultPbtSeed]다.
/// - 실패를 재현할 때: 출력된 `(seed N)`으로 `PBT_SEED=N flutter test <파일>`
/// - 다른 입력을 탐색할 때: `PBT_SEED=$RANDOM flutter test`
void configurePbt() {
  KiriCheck.seed = int.tryParse(Platform.environment['PBT_SEED'] ?? '') ?? defaultPbtSeed;
  KiriCheck.maxExamples = pbtExamples;
}
