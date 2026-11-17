// 대상 파일의 라인 커버리지가 기준에 미치는지 검사한다.
//
// 사용법: dart tool/coverage_gate.dart [lcov 파일 경로]
// 경로를 주지 않으면 coverage/lcov.info 를 읽는다. 먼저 `flutter test --coverage` 로 만들어야 한다.
// 종료 코드: 통과 0, 실패 1.
import 'dart:io';
import 'dart:math' show max;

/// 커버리지를 검사하는 파일. 저장소 루트 기준 경로이며, 보고서도 이 순서로 출력한다.
const coverageTargets = <String>[
  'lib/features/player/data/backends/phone_backend.dart',
  'lib/features/player/data/backends/dlna_backend.dart',
  'lib/features/dlna/data/dlna_manager.dart',
  'lib/features/player/data/wave_audio_handler.dart',
];

/// 대상 파일마다 넘어야 하는 라인 커버리지(%). 정확히 이 값이면 통과다.
const coverageThresholdPercent = 80;

/// 경로를 주지 않았을 때 읽는 lcov 파일. `flutter test --coverage`가 만드는 위치다.
const _defaultLcovPath = 'coverage/lcov.info';

/// 보고서의 비율 칸 폭. `기록 없음`의 화면 폭(한글은 두 칸)에 맞춘다.
const _ratioColumnWidth = 9;

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
List<FileCoverage> parseLcov(String content) => [
      for (final MapEntry(key: path, value: lines) in _parseLineHits(content).entries)
        FileCoverage(path: path, hitLines: _countHit(lines), totalLines: lines.length),
    ];

/// lcov 내용에서 [targets]의 커버리지를 계산해 [thresholdPercent] 기준으로 판정한다.
GateResult evaluateCoverage(
  String lcovContent, {
  List<String> targets = coverageTargets,
  int thresholdPercent = coverageThresholdPercent,
}) {
  final files = _parseLineHits(lcovContent);
  final results = <TargetResult>[];
  for (final target in targets) {
    // 절대 경로와 상대 경로처럼 한 대상에 맞는 기록이 여럿이면 줄 번호별로 합친다.
    final lines = <int, bool>{};
    for (final MapEntry(key: path, value: fileLines) in files.entries) {
      if (_matchesTarget(path, target)) _mergeLineHits(lines, fileLines);
    }
    final hit = _countHit(lines);
    final total = lines.length;
    final passed = total > 0 && hit * 100 >= thresholdPercent * total;
    results.add(
      TargetResult(
        target: target,
        hitLines: hit,
        totalLines: total,
        passed: passed,
        // 올림(기준값 × 전체 줄 / 100) − 실행된 줄
        missingLines: passed || total == 0 ? 0 : (thresholdPercent * total + 99) ~/ 100 - hit,
      ),
    );
  }
  return GateResult(thresholdPercent: thresholdPercent, targets: results);
}

/// 검사 결과를 사람이 읽는 보고서로 만든다. 줄 끝마다 줄바꿈이 있다.
String formatReport(GateResult result) {
  final counts = [for (final target in result.targets) '${target.hitLines}/${target.totalLines}'];
  final pathWidth = result.targets.fold(0, (width, target) => max(width, target.target.length));
  final countWidth = counts.fold(0, (width, count) => max(width, count.length));

  final out = StringBuffer();
  for (final (index, target) in result.targets.indexed) {
    final ratio =
        target.hasNoRecord ? '기록 없음' : _percent(target.hitLines, target.totalLines).padLeft(_ratioColumnWidth);
    out.write('${target.target.padRight(pathWidth)}  ${counts[index].padLeft(countWidth)}  $ratio  ');
    out.write(target.passed ? '통과' : '실패');
    if (!target.passed && !target.hasNoRecord) out.write('  ${target.missingLines}줄 부족');
    out.write('\n');
  }
  out.write('전체 ${result.passed ? '통과' : '실패'} (기준 ${result.thresholdPercent}%)\n');
  return out.toString();
}

/// 검사를 실행해 보고서를 [out]에 쓰고 종료 코드를 돌려준다.
///
/// [args]의 첫 값이 lcov 파일 경로다. 없으면 `coverage/lcov.info`를 읽는다.
int runCoverageGate(List<String> args, StringSink out) {
  final path = args.isEmpty ? _defaultLcovPath : args.first;
  final String content;
  try {
    content = File(path).readAsStringSync();
  } on FileSystemException {
    out.writeln('커버리지 파일을 읽을 수 없습니다: $path');
    out.writeln('먼저 `flutter test --coverage` 를 실행하세요.');
    return 1;
  }
  final result = evaluateCoverage(content);
  out.write(formatReport(result));
  return result.passed ? 0 : 1;
}

/// lcov 내용을 파일 경로 → 줄 번호 → 실행 여부로 바꾼다. 같은 파일 · 같은 줄은 합친다.
Map<String, Map<int, bool>> _parseLineHits(String content) {
  final files = <String, Map<int, bool>>{};
  Map<int, bool>? current;
  for (final rawLine in content.split('\n')) {
    final line = rawLine.trim();
    if (line.startsWith('SF:')) {
      final path = line.substring(3).trim().replaceAll(r'\', '/');
      current = files.putIfAbsent(path, () => {});
    } else if (line == 'end_of_record') {
      current = null;
    } else if (line.startsWith('DA:') && current != null) {
      final fields = line.substring(3).split(',');
      if (fields.length < 2) continue;
      final number = int.tryParse(fields[0]);
      final count = int.tryParse(fields[1]);
      if (number == null || count == null) continue;
      _mergeLineHit(current, number, count >= 1);
    }
  }
  return files;
}

/// lcov의 [path]가 [target]의 기록인지. 같거나 `/<대상 경로>`로 끝나면 맞다(절대 경로 허용).
bool _matchesTarget(String path, String target) => path == target || path.endsWith('/$target');

/// 줄 하나의 기록을 [into]에 합친다. 한 번이라도 실행된 줄은 실행된 줄이다.
void _mergeLineHit(Map<int, bool> into, int number, bool hit) {
  into[number] = (into[number] ?? false) || hit;
}

/// [from]의 줄 기록을 [into]에 합친다.
void _mergeLineHits(Map<int, bool> into, Map<int, bool> from) {
  for (final MapEntry(key: number, value: hit) in from.entries) {
    _mergeLineHit(into, number, hit);
  }
}

int _countHit(Map<int, bool> lines) => lines.values.where((hit) => hit).length;

/// 비율을 소수 첫째 자리까지 버림해 쓴다. [total]은 1 이상이어야 한다.
String _percent(int hit, int total) {
  final tenths = hit * 1000 ~/ total;
  return '${tenths ~/ 10}.${tenths % 10}%';
}

void main(List<String> args) {
  exitCode = runCoverageGate(args, stdout);
}
