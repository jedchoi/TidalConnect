// 대상 파일의 라인 커버리지가 기준에 미치는지 검사한다.
//
// 사용법: dart run tool/coverage_gate.dart [lcov 파일 경로]
// 경로를 주지 않으면 coverage/lcov.info 를 읽는다. 먼저 `flutter test --coverage` 로 만들어야 한다.
// 종료 코드: 통과 0, 실패 1.
import 'dart:io';

/// 커버리지를 검사하는 파일. 저장소 루트 기준 경로이며, 보고서도 이 순서로 출력한다.
const coverageTargets = <String>[
  'lib/features/player/data/backends/phone_backend.dart',
  'lib/features/player/data/backends/dlna_backend.dart',
  'lib/features/dlna/data/dlna_manager.dart',
  'lib/features/player/data/wave_audio_handler.dart',
];

/// 대상 파일마다 넘어야 하는 라인 커버리지(%). 정확히 이 값이면 통과다.
const coverageThresholdPercent = 80;

/// lcov에 기록된 파일 하나의 줄 수.
class FileCoverage {
  const FileCoverage({required this.path, required this.hitLines, required this.totalLines});

  /// lcov의 `SF:`에 적힌 경로. 구분자는 `/`로 바꾼 값이다.
  final String path;

  /// 한 번 이상 실행된 줄 수.
  final int hitLines;

  /// 기록된 줄 수.
  final int totalLines;
}

/// 대상 파일 하나의 검사 결과.
class TargetResult {
  const TargetResult({
    required this.target,
    required this.hitLines,
    required this.totalLines,
    required this.passed,
    required this.missingLines,
  });

  /// [coverageTargets]에 적힌 경로.
  final String target;

  /// 한 번 이상 실행된 줄 수. 기록이 없으면 0.
  final int hitLines;

  /// 기록된 줄 수. 기록이 없으면 0.
  final int totalLines;

  /// 기준을 넘었는지. 기록이 없으면 false.
  final bool passed;

  /// 통과하려면 더 실행되어야 하는 최소 줄 수. 통과했거나 기록이 없으면 0.
  final int missingLines;

  /// lcov에 이 대상의 줄 기록이 하나도 없는지.
  bool get hasNoRecord => totalLines == 0;
}

/// 전체 검사 결과.
class GateResult {
  const GateResult({required this.thresholdPercent, required this.targets});

  /// 검사에 쓴 기준값(%).
  final int thresholdPercent;

  /// 대상별 결과. 대상 목록의 순서와 같다.
  final List<TargetResult> targets;

  /// 모든 대상이 통과했는지.
  bool get passed => targets.every((target) => target.passed);
}

/// lcov 내용을 파일별 줄 수로 바꾼다. 해석할 수 없는 줄은 무시한다.
List<FileCoverage> parseLcov(String content) => const [];

/// lcov 내용에서 [targets]의 커버리지를 계산해 [thresholdPercent] 기준으로 판정한다.
GateResult evaluateCoverage(
  String lcovContent, {
  List<String> targets = coverageTargets,
  int thresholdPercent = coverageThresholdPercent,
}) =>
    GateResult(thresholdPercent: thresholdPercent, targets: const []);

/// 검사 결과를 사람이 읽는 보고서로 만든다. 줄 끝마다 줄바꿈이 있다.
String formatReport(GateResult result) => '';

/// 검사를 실행해 보고서를 [out]에 쓰고 종료 코드를 돌려준다.
///
/// [args]의 첫 값이 lcov 파일 경로다. 없으면 `coverage/lcov.info`를 읽는다.
int runCoverageGate(List<String> args, StringSink out) => 1;

void main(List<String> args) {
  exitCode = runCoverageGate(args, stdout);
}
