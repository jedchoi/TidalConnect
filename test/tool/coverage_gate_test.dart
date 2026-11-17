import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kiri_check/kiri_check.dart' as kc;

import '../../tool/coverage_gate.dart';
import '../helpers/pbt_config.dart';

// 커버리지 검사 스크립트(tool/coverage_gate.dart) 테스트. 규칙 ID(GT-xx)와 속성 ID(P-GT-x)는
// aidlc-docs/construction/plans/ci-quality-gate-code-generation-plan.md 의 "검사 규칙 (GT) 과 속성 (P-GT)" 절과
// "규칙 보완" 표를 가리킨다. 행 구성은 aidlc-docs/construction/ci-quality-gate/code/red-seam-table.md 를 따른다.

const _phoneBackend = 'lib/features/player/data/backends/phone_backend.dart';
const _dlnaBackend = 'lib/features/player/data/backends/dlna_backend.dart';
const _dlnaManager = 'lib/features/dlna/data/dlna_manager.dart';
const _waveAudioHandler = 'lib/features/player/data/wave_audio_handler.dart';

/// lcov 기록 하나. 줄 1..[total] 가운데 앞의 [hit]줄은 횟수 1, 나머지는 0이다.
String _rec(String path, int hit, int total) {
  final out = StringBuffer('SF:$path\n');
  for (var line = 1; line <= total; line++) {
    out.write('DA:$line,${line <= hit ? 1 : 0}\n');
  }
  out.write('end_of_record\n');
  return out.toString();
}

/// 줄 기록이 있는 파일만 (경로, 실행된 줄, 전체 줄)로 바꾼다. 결과의 순서와 줄 0개 파일은 규칙이 정하지 않는다.
List<(String, int, int)> _entries(List<FileCoverage> files) =>
    [for (final f in files.where((f) => f.totalLines > 0)) (f.path, f.hitLines, f.totalLines)];

/// 보고서를 줄 목록으로 바꾼다. 줄바꿈으로 끝나고 줄 수가 대상 수 + 1인지 먼저 확인한다.
List<String> _reportLines(GateResult result) {
  final report = formatReport(result);
  expect(report, endsWith('\n'), reason: '보고서는 줄바꿈으로 끝난다');
  final lines = report.substring(0, report.length - 1).split('\n');
  expect(lines, hasLength(result.targets.length + 1), reason: report);
  return lines;
}

GateResult _single(int hit, int total, {required bool passed, required int missing, int threshold = 80}) => GateResult(
      thresholdPercent: threshold,
      targets: [
        TargetResult(target: 'lib/a.dart', hitLines: hit, totalLines: total, passed: passed, missingLines: missing),
      ],
    );

const _r1 = GateResult(
  thresholdPercent: 80,
  targets: [
    TargetResult(target: 'lib/b.dart', hitLines: 4, totalLines: 5, passed: true, missingLines: 0),
    TargetResult(target: 'lib/a.dart', hitLines: 799, totalLines: 1000, passed: false, missingLines: 1),
    TargetResult(target: 'lib/c.dart', hitLines: 0, totalLines: 0, passed: false, missingLines: 0),
  ],
);

// ---- 속성 테스트의 생성기. 값은 kiri_check 의 조합 함수로만 만든다. ----

/// 파일별 줄 번호 → 실행 횟수.
typedef _Record = Map<String, Map<int, int>>;

/// 실행 횟수: 0이 셋 중 하나꼴, 나머지는 1~1000.
kc.Arbitrary<int> _counts() => kc.frequency([(1, kc.constant(0)), (2, kc.integer(min: 1, max: 1000))]).map(
      (v) => v as int,
    );

/// 한 파일의 줄 기록: 줄 번호 1~500(중복 없음) → 횟수.
kc.Arbitrary<Map<int, int>> _lineHits({int minLines = 0, int maxLines = 40}) => kc
    .list(
      kc.combine2(kc.integer(min: 1, max: 500), _counts()),
      minLength: minLines,
      maxLength: maxLines,
      uniqueBy: (a, b) => a.$1 == b.$1,
    )
    .map((lines) => {for (final line in lines) line.$1: line.$2});

/// 실행 기록: 파일 0~6개(경로 `lib/gen/f_<0~99>.dart`, 중복 없음), 파일마다 줄 0~40개.
kc.Arbitrary<_Record> _records() => kc
    .list(
      kc.combine2(kc.integer(min: 0, max: 99), _lineHits()),
      minLength: 0,
      maxLength: 6,
      uniqueBy: (a, b) => a.$1 == b.$1,
    )
    .map((files) => {for (final file in files) 'lib/gen/f_${file.$1}.dart': file.$2});

/// 변형에 쓰는 선택 값 32개(0~1000).
kc.Arbitrary<List<int>> _choices() => kc.list(kc.integer(min: 0, max: 1000), minLength: 32, maxLength: 32);

String _chunk(String path, Iterable<MapEntry<int, int>> lines) {
  final out = StringBuffer('SF:$path\n');
  for (final line in lines) {
    out.write('DA:${line.key},${line.value}\n');
  }
  out.write('end_of_record\n');
  return out.toString();
}

/// 표준 형태: 파일마다 `SF:` / `DA:` … / `end_of_record` 한 덩어리.
String _writeLcov(_Record record) => [for (final file in record.entries) _chunk(file.key, file.value.entries)].join();

/// 기록에서 직접 센 값: 줄이 있는 파일의 (경로, 실행된 줄, 전체 줄).
List<(String, int, int)> _counted(_Record record) => [
      for (final file in record.entries)
        if (file.value.isNotEmpty) (file.key, file.value.values.where((count) => count >= 1).length, file.value.length),
    ];

/// 파일마다 줄 기록을 1~3 덩어리로 나누고, 모든 덩어리의 순서를 섞어 쓴다.
String _writeSplitAndShuffled(_Record record, List<int> choices) {
  int pick(int i) => choices[i % choices.length];
  final chunks = <String>[];
  var fileIndex = 0;
  for (final file in record.entries) {
    final chunkCount = 1 + pick(fileIndex) % 3;
    final parts = List.generate(chunkCount, (_) => <MapEntry<int, int>>[]);
    var lineIndex = 0;
    for (final line in file.value.entries) {
      parts[pick(fileIndex * 7 + lineIndex + 1) % chunkCount].add(line);
      lineIndex++;
    }
    chunks.addAll(parts.map((part) => _chunk(file.key, part)));
    fileIndex++;
  }
  final order = List.generate(chunks.length, (i) => i)
    ..sort((a, b) {
      final byKey = pick(a + 11).compareTo(pick(b + 11));
      return byKey != 0 ? byKey : a.compareTo(b);
    });
  return [for (final i in order) chunks[i]].join();
}

/// 대상이 아닌 파일 하나: (경로 종류 0~2, 번호 0~9, 줄 기록, 끼울 위치 0~10).
typedef _Noise = (int, int, Map<int, int>, int);

/// P-GT-2 의 입력: 대상별 줄 기록(null 이면 기록 없음), 잡음 파일, 기준값.
typedef _NoiseCase = (List<Map<int, int>?>, List<_Noise>, int);

kc.Arbitrary<_NoiseCase> _noiseCases() {
  final target = kc.frequency([(1, kc.null_()), (3, _lineHits(minLines: 1))]).map((v) => v as Map<int, int>?);
  final noise = kc.combine4(
    kc.integer(min: 0, max: 2),
    kc.integer(min: 0, max: 9),
    _lineHits(),
    kc.integer(min: 0, max: 10),
  );
  return kc.combine3(
    kc.list(target, minLength: 1, maxLength: 4),
    kc.list(noise, minLength: 0, maxLength: 6),
    kc.integer(min: 1, max: 100),
  );
}

/// P-GT-3 의 대상 하나: (전체 줄, 실행된 줄, 전체 줄이 0일 때 `SF:`만 쓸지).
typedef _Counts = (int, int, bool);

kc.Arbitrary<_Counts> _targetCounts() {
  final total = kc.frequency([(1, kc.constant(0)), (5, kc.integer(min: 1, max: 300))]).map((v) => v as int);
  // 실행된 줄: 전체와 같음 2, 0~전체에서 고름 2, 0이 1의 비율.
  final hitKind = kc.frequency([(2, kc.constant(0)), (2, kc.constant(1)), (1, kc.constant(2))]).map((v) => v as int);
  return kc.combine4(total, hitKind, kc.integer(min: 0, max: 300), kc.boolean()).map((v) {
    final hit = switch (v.$2) { 0 => v.$1, 1 => v.$3 % (v.$1 + 1), _ => 0 };
    return (v.$1, hit, v.$4);
  });
}

/// 기준값: 80이 2, 1~100에서 고름이 1의 비율.
kc.Arbitrary<int> _thresholds() => kc.frequency([(2, kc.constant(80)), (1, kc.integer(min: 1, max: 100))]).map(
      (v) => v as int,
    );

/// P-GT-5 의 입력: 실패하는 대상의 (전체 줄 1~300, 기준값 1~100, 실행된 줄 0~전체).
kc.Arbitrary<(int, int, int)> _failingTargets() => kc
    .combine3(kc.integer(min: 1, max: 300), kc.integer(min: 1, max: 100), kc.integer(min: 0, max: 300))
    .map((v) => (v.$1, v.$2, v.$3 % (v.$1 + 1)))
    .filter((v) => v.$3 * 100 < v.$2 * v.$1);

void main() {
  configurePbt();

  group('parseLcov', () {
    test('[GT-01] SF · DA · end_of_record 로 파일별 전체 줄 수와 실행된 줄 수를 센다', () {
      // GT-01: 전체 줄 = 기록된 줄 번호 개수, 실행된 줄 = 횟수 1 이상인 줄 번호 개수 (횟수를 더하거나 0 을 실행으로 세면 실패)
      const content = 'SF:lib/a.dart\nDA:1,1\nDA:2,0\nDA:3,5\nend_of_record\n'
          'SF:lib/b.dart\nDA:10,0\nDA:20,0\nend_of_record\n';

      expect(_entries(parseLcov(content)), unorderedEquals([('lib/a.dart', 2, 3), ('lib/b.dart', 0, 2)]));
    });

    test('[GT-02] 같은 파일 · 같은 줄 번호가 여러 번 나오면 줄 번호별로 합친다', () {
      // GT-02: 한 번이라도 횟수가 1 이상이면 실행된 줄 (나중 기록으로 덮어쓰거나 파일 항목을 둘로 만들면 실패)
      const repeatedFile = 'SF:lib/a.dart\nDA:1,0\nDA:2,1\nend_of_record\n'
          'SF:lib/a.dart\nDA:1,3\nDA:3,0\nend_of_record\n';
      const repeatedLine = 'SF:lib/b.dart\nDA:7,0\nDA:7,0\nDA:7,2\nend_of_record\n';

      expect(_entries(parseLcov(repeatedFile)), [('lib/a.dart', 2, 3)]);
      expect(_entries(parseLcov(repeatedLine)), [('lib/b.dart', 1, 1)]);
    });

    test('[GT-03] 쓰지 않는 줄과 해석할 수 없는 줄은 예외 없이 무시한다', () {
      // GT-03: 그 밖의 줄 · 깨진 DA · SF 앞의 DA 는 무시, 체크섬은 무시 (LF/LH 를 쓰거나 깨진 줄에서 던지면 실패)
      const mixed = 'TN:\n\nDA:9,9\nSF:lib/a.dart\nFN:1,main\nFNDA:1,main\nLF:99\nLH:99\nBRDA:1,0,0,1\n'
          'DA:1,1\nDA:abc,1\nDA:2,x\nDA:3\nDA:\nDA:4,0,abc123\nDA:5,2,deadbeef\n\nend_of_record\n';
      expect(_entries(parseLcov(mixed)), [('lib/a.dart', 2, 3)]);

      for (final nothing in ['', '\n\n', 'TN:\nLF:3\nDA:1,1\nDA:x\n']) {
        expect(_entries(parseLcov(nothing)), isEmpty, reason: nothing);
      }

      // 보완: 줄은 앞뒤 공백을 뗀 뒤 해석하고, 줄 끝이 \r\n 이어도 같다.
      const crlf = 'SF:lib/a.dart\r\nDA:1,1\r\nDA:2,0\r\n\tDA:3,1 \r\nend_of_record\r\nDA:9,1\r\n'
          'SF:lib/b.dart\r\nDA:1,1\r\nend_of_record\r\n';
      expect(_entries(parseLcov(crlf)), unorderedEquals([('lib/a.dart', 2, 3), ('lib/b.dart', 1, 1)]));

      // 보완: SF 는 앞 기록이 닫히지 않았어도 새 파일을 시작하고, 내용이 끝나면 기록도 닫힌다.
      const unclosed = 'SF:lib/a.dart\nDA:1,1\nSF:lib/b.dart\nDA:1,0\nDA:2,1';
      expect(_entries(parseLcov(unclosed)), unorderedEquals([('lib/a.dart', 1, 1), ('lib/b.dart', 1, 2)]));

      // 보완: end_of_record 뒤, 다음 SF 앞의 DA 는 무시한다.
      const afterEnd = 'SF:lib/a.dart\nDA:1,1\nend_of_record\nDA:2,1\nDA:3,0\n'
          'SF:lib/b.dart\nDA:1,0\nend_of_record\n';
      expect(_entries(parseLcov(afterEnd)), unorderedEquals([('lib/a.dart', 1, 1), ('lib/b.dart', 0, 1)]));
    });

    test(r'[GT-04] 돌려주는 경로는 \ 를 / 로 바꾸고 앞뒤 공백을 뗀 값이다', () {
      // GT-04 · GT-01 보완: FileCoverage.path 는 정리된 경로 (SF 의 글자를 그대로 돌려주면 실패)
      expect(_entries(parseLcov('SF:C:\\work\\app\\lib\\a.dart\nDA:1,1\nend_of_record\n')), [
        ('C:/work/app/lib/a.dart', 1, 1),
      ]);
      expect(_entries(parseLcov('SF:  lib\\b.dart  \nDA:1,0\nend_of_record\n')), [('lib/b.dart', 0, 1)]);
    });
  });

  group('evaluateCoverage', () {
    test('[GT-04] SF 가 대상 경로와 같거나 /<대상 경로> 로 끝나면 그 대상의 기록이다', () {
      // GT-04: 절대 경로 · \ 구분자 · 앞뒤 공백 허용, 경계는 / (단순 endsWith 나 contains 로 비교하면 실패)
      const target = 'lib/a/b.dart';
      GateResult evaluateWithSf(String sf) => evaluateCoverage(
            'SF:$sf\nDA:1,1\nDA:2,1\nDA:3,1\nDA:4,0\nend_of_record\n',
            targets: const [target],
          );

      for (final sf in [
        'lib/a/b.dart',
        '/Users/ci/work/app/lib/a/b.dart',
        r'C:\work\app\lib\a\b.dart',
        r'lib\a\b.dart',
        './lib/a/b.dart',
        '  lib/a/b.dart  ',
      ]) {
        final result = evaluateWithSf(sf);
        expect(result.targets, hasLength(1), reason: sf);
        expect(result.targets[0].hitLines, 3, reason: sf);
        expect(result.targets[0].totalLines, 4, reason: sf);
      }

      for (final sf in ['/work/xlib/a/b.dart', 'lib/a/b.dart.bak', 'lib/a/c.dart']) {
        final result = evaluateWithSf(sf);
        expect(result.targets, hasLength(1), reason: sf);
        expect(result.targets[0].totalLines, 0, reason: sf);
        expect(result.targets[0].hasNoRecord, isTrue, reason: sf);
        expect(result.targets[0].passed, isFalse, reason: sf);
      }

      // 보완: 한 대상에 맞는 SF 가 여럿이면 줄 번호별로 합친다.
      final merged = evaluateCoverage(
        'SF:/Users/ci/work/app/lib/a/b.dart\nDA:1,1\nDA:2,0\nend_of_record\n'
        'SF:lib/a/b.dart\nDA:2,1\nDA:3,0\nend_of_record\n',
        targets: const [target],
      );
      expect(merged.targets, hasLength(1));
      expect(merged.targets[0].hitLines, 2);
      expect(merged.targets[0].totalLines, 3);
    });

    test('[GT-05] 실행된 줄 × 100 ≥ 기준값 × 전체 줄이면 통과하고, 정확히 기준값이면 통과다', () {
      // GT-05: 정수 비교, 반올림 없음 (> 로 비교하면 800/1000 에서, 반올림하면 799/1000 에서 실패)
      const cases = <(int?, int, int, bool)>[
        (null, 799, 1000, false),
        (null, 800, 1000, true),
        (null, 801, 1000, true),
        (null, 4, 5, true),
        (null, 3, 4, false),
        (null, 79, 100, false),
        (null, 1, 1, true),
        (null, 0, 1, false),
        (100, 999, 1000, false),
        (100, 1000, 1000, true),
        (50, 1, 2, true),
        (50, 1, 3, false),
      ];

      for (final (threshold, hit, total, passed) in cases) {
        final content = _rec('lib/a.dart', hit, total);
        final result = threshold == null
            ? evaluateCoverage(content, targets: const ['lib/a.dart'])
            : evaluateCoverage(content, targets: const ['lib/a.dart'], thresholdPercent: threshold);
        final reason = '$hit/$total, 기준값 ${threshold ?? '기본'}';

        expect(result.targets, hasLength(1), reason: reason);
        expect(result.targets[0].passed, passed, reason: reason);
        expect(result.thresholdPercent, threshold ?? 80, reason: reason);
      }
    });

    test('[GT-06] 대상의 기록이 없거나 전체 줄 수가 0 이면 실패다', () {
      // GT-06: 기록 없음은 실패 (없는 대상을 건너뛰거나 0/0 을 통과로 보면 실패)
      const targets = ['lib/a.dart', 'lib/b.dart'];

      final empty = evaluateCoverage('', targets: targets);
      expect(empty.targets, hasLength(2));
      for (final target in empty.targets) {
        expect(target.hitLines, 0);
        expect(target.totalLines, 0);
        expect(target.hasNoRecord, isTrue);
        expect(target.passed, isFalse);
      }
      expect(empty.passed, isFalse);

      final b = _rec('lib/b.dart', 4, 5);
      final contents = {
        '대상 기록 없음': b,
        '줄 기록 0개': 'SF:lib/a.dart\nend_of_record\n$b',
        '해석할 수 없는 줄뿐': 'SF:lib/a.dart\nDA:x,1\nDA:3\nend_of_record\n$b',
      };
      for (final MapEntry(key: reason, value: content) in contents.entries) {
        final result = evaluateCoverage(content, targets: targets);
        expect(result.targets, hasLength(2), reason: reason);
        expect(result.targets[0].hitLines, 0, reason: reason);
        expect(result.targets[0].totalLines, 0, reason: reason);
        expect(result.targets[0].hasNoRecord, isTrue, reason: reason);
        expect(result.targets[0].passed, isFalse, reason: reason);
        expect(result.targets[1].hitLines, 4, reason: reason);
        expect(result.targets[1].totalLines, 5, reason: reason);
        expect(result.targets[1].passed, isTrue, reason: reason);
        expect(result.passed, isFalse, reason: reason);
      }
    });

    test('[GT-07] 대상이 아닌 파일의 기록은 결과에 영향을 주지 않는다', () {
      // GT-07: 대상만 본다 (전체 평균을 내거나 이름이 비슷한 파일을 대상에 합치면 실패)
      final content = [
        _rec('lib/other.dart', 0, 50),
        _rec('test/a_test.dart', 0, 10),
        _rec('lib/a.dart', 4, 5),
        _rec('lib/a.dart.orig', 0, 9),
        _rec('lib/aa.dart', 0, 9),
      ].join();

      final result = evaluateCoverage(content, targets: const ['lib/a.dart']);

      expect(result.targets, hasLength(1));
      expect(result.targets[0].hitLines, 4);
      expect(result.targets[0].totalLines, 5);
      expect(result.targets[0].passed, isTrue);
      expect(result.passed, isTrue);
    });

    test('[GT-08] 전체 판정은 모든 대상이 통과할 때만 통과다', () {
      // GT-08: 하나라도 실패 · 기록 없음이면 전체 실패 (any 로 판정하거나 기록 없는 대상을 빼면 실패)
      const targets = ['lib/a.dart', 'lib/b.dart', 'lib/c.dart'];
      final cases = <(String, List<bool>, bool)>[
        (_rec('lib/a.dart', 4, 5) + _rec('lib/b.dart', 5, 5) + _rec('lib/c.dart', 800, 1000), [true, true, true], true),
        (_rec('lib/a.dart', 4, 5) + _rec('lib/b.dart', 3, 5) + _rec('lib/c.dart', 5, 5), [true, false, true], false),
        (_rec('lib/a.dart', 4, 5) + _rec('lib/b.dart', 5, 5), [true, true, false], false),
        (_rec('lib/a.dart', 0, 5) + _rec('lib/b.dart', 0, 5) + _rec('lib/c.dart', 0, 5), [false, false, false], false),
      ];

      for (final (content, eachPassed, passed) in cases) {
        final result = evaluateCoverage(content, targets: targets);
        expect(result.targets, hasLength(3), reason: '$eachPassed');
        expect([for (final target in result.targets) target.passed], eachPassed);
        expect(result.passed, passed, reason: '$eachPassed');
      }
    });

    test('[GT-13] 인자를 생략하면 대상 4개를 정해진 순서로, 기준값 80 으로 검사한다', () {
      // GT-13: 기본 대상 4개와 기준값 80 (대상이 빠지거나 순서가 lcov 순서를 따르거나 기준값이 다르면 실패)
      final content = [
        _rec(_waveAudioHandler, 5, 5),
        _rec(_dlnaManager, 79, 100),
        _rec(_dlnaBackend, 4, 5),
        _rec(_phoneBackend, 800, 1000),
      ].join();

      final result = evaluateCoverage(content);

      expect(result.targets, hasLength(4));
      expect([
        for (final target in result.targets) target.target
      ], [
        'lib/features/player/data/backends/phone_backend.dart',
        'lib/features/player/data/backends/dlna_backend.dart',
        'lib/features/dlna/data/dlna_manager.dart',
        'lib/features/player/data/wave_audio_handler.dart',
      ]);
      expect(result.thresholdPercent, 80);
      expect([for (final target in result.targets) target.passed], [true, true, false, true]);
      expect(result.passed, isFalse);
    });

    test('[GT-10] 모자란 줄 수는 통과하는 데 더 실행되어야 하는 최소 줄 수다', () {
      // GT-10: 올림(기준값 × 전체 줄 / 100) − 실행된 줄 (내림 · 반올림하거나 통과한 대상에 값을 주면 실패)
      const cases = <(int?, int, int, int)>[
        (null, 799, 1000, 1),
        (null, 0, 10, 8),
        (null, 5, 7, 1),
        (null, 50, 101, 31),
        (null, 0, 1, 1),
        (null, 3, 5, 1),
        (null, 4, 5, 0),
        (100, 7, 10, 3),
      ];

      for (final (threshold, hit, total, missing) in cases) {
        final content = _rec('lib/a.dart', hit, total);
        final result = threshold == null
            ? evaluateCoverage(content, targets: const ['lib/a.dart'])
            : evaluateCoverage(content, targets: const ['lib/a.dart'], thresholdPercent: threshold);
        final reason = '$hit/$total, 기준값 ${threshold ?? '기본'}';

        expect(result.targets, hasLength(1), reason: reason);
        expect(result.targets[0].missingLines, missing, reason: reason);
      }

      // GT-06 보완: 기록이 없는 대상의 모자란 줄 수는 0 이다.
      final noRecord = evaluateCoverage('', targets: const ['lib/a.dart']);
      expect(noRecord.targets, hasLength(1));
      expect(noRecord.targets[0].missingLines, 0);
    });
  });

  group('formatReport', () {
    test('[GT-09] 대상을 결과의 순서대로 한 줄씩 쓰고 마지막 줄에 전체 판정과 기준값을 쓴다', () {
      // GT-09: 줄 수 = 대상 수 + 1, 줄마다 경로 · 실행/전체 · 판정 (순서를 바꾸거나 통과한 대상을 빼거나 기준값을 박아 쓰면 실패)
      final lines = _reportLines(_r1);

      expect(lines, hasLength(4));
      expect(lines[0], allOf(contains('lib/b.dart'), contains('4/5'), contains('통과'), isNot(contains('실패'))));
      expect(lines[1], allOf(contains('lib/a.dart'), contains('799/1000'), contains('실패'), isNot(contains('통과'))));
      expect(lines[2], allOf(contains('lib/c.dart'), contains('실패')));
      expect(lines[3], allOf(contains('실패'), contains('80%'), isNot(contains('통과'))));

      final allPassed = _reportLines(_single(3, 4, passed: true, missing: 0, threshold: 75));
      expect(allPassed, hasLength(2));
      expect(allPassed[1], allOf(contains('통과'), contains('75%')));
    });

    test('[GT-09] 비율은 소수 첫째 자리까지 버림해 % 와 함께 쓴다', () {
      // GT-09: 버림, 항상 소수 한 자리 (반올림하면 2/3 · 1999/2000 · 1/16 에서, 정수로 쓰면 4/5 · 10/10 에서 실패)
      final cases = <(GateResult, String, String?)>[
        (_single(799, 1000, passed: false, missing: 1), '79.9%', null),
        (_single(2, 3, passed: false, missing: 1), '66.6%', '66.7'),
        (_single(1999, 2000, passed: true, missing: 0), '99.9%', '100.0'),
        (_single(1, 3, passed: false, missing: 2), '33.3%', null),
        (_single(1, 16, passed: false, missing: 12), '6.2%', '6.3'),
        (_single(1, 8, passed: false, missing: 6), '12.5%', null),
        (_single(0, 10, passed: false, missing: 8), '0.0%', null),
        (_single(4, 5, passed: true, missing: 0), '80.0%', null),
        (_single(10, 10, passed: true, missing: 0), '100.0%', null),
      ];

      for (final (result, ratio, rounded) in cases) {
        final line = _reportLines(result)[0];
        expect(line, contains(ratio));
        if (rounded != null) expect(line, isNot(contains(rounded)));
      }
    });

    test('[GT-09] 기록이 없는 대상은 비율 자리에 기록 없음을 쓴다', () {
      // GT-09: 기록 없는 줄에는 0/0 과 기록 없음, 비율은 없음 (0.0% 로 쓰거나 0 으로 나누면 실패)
      final line = _reportLines(_r1)[2];

      expect(line, allOf(contains('기록 없음'), contains('0/0'), isNot(contains('%'))));
    });

    test('[GT-10] 실패한 대상의 줄 끝에 모자란 줄 수를 덧붙인다', () {
      // GT-10: 실패한 줄에만 N줄 부족 (통과 · 기록 없는 줄에 쓰거나 줄 수를 빼먹으면 실패)
      final lines = _reportLines(_r1);

      expect(lines[1], contains('1줄 부족'));
      expect(lines[0], isNot(contains('부족')));
      expect(lines[2], isNot(contains('부족')));

      const other = GateResult(
        thresholdPercent: 80,
        targets: [
          TargetResult(target: 'lib/d.dart', hitLines: 50, totalLines: 101, passed: false, missingLines: 31),
        ],
      );
      expect(_reportLines(other)[0], contains('31줄 부족'));
    });
  });

  group('runCoverageGate', () {
    Directory tempDir() {
      final dir = Directory.systemTemp.createTempSync('coverage_gate_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      return dir;
    }

    test('[GT-11] lcov 파일이 없거나 읽을 수 없으면 1 을 돌려주고 flutter test --coverage 를 안내한다', () {
      // GT-11: 파일 없음 · 읽기 실패는 종료 코드 1 과 안내 (예외를 던지거나 조용히 실패하면 실패)
      final dir = tempDir();

      for (final path in ['${dir.path}/없음.info', dir.path]) {
        final out = StringBuffer();
        int? code;

        expect(() => code = runCoverageGate([path], out), returnsNormally, reason: path);
        expect(code, 1, reason: path);
        expect(out.toString(), contains('flutter test --coverage'), reason: path);
      }
    });

    test('[GT-12] 첫 인자의 lcov 를 읽어 통과면 0, 실패면 1 을 돌려주고 보고서를 출력한다', () {
      // GT-12: 종료 코드 통과 0 · 실패 1, 첫 인자가 경로 (늘 같은 값을 돌려주거나 보고서를 쓰지 않으면 실패)
      final dir = tempDir();
      const targets = [_phoneBackend, _dlnaBackend, _dlnaManager, _waveAudioHandler];
      (int, String) run(String name, String content) {
        final file = File('${dir.path}/$name')..writeAsStringSync(content);
        final out = StringBuffer();
        return (runCoverageGate([file.path], out), out.toString());
      }

      final (passCode, passOut) = run(
        'pass.info',
        _rec(_phoneBackend, 4, 5) +
            _rec(_dlnaBackend, 5, 5) +
            _rec(_dlnaManager, 800, 1000) +
            _rec(_waveAudioHandler, 98, 100),
      );
      expect(passCode, 0);
      expect(passOut, allOf(targets.map(contains).toList()));

      final (failCode, failOut) = run(
        'fail.info',
        _rec(_phoneBackend, 4, 5) +
            _rec(_dlnaBackend, 5, 5) +
            _rec(_dlnaManager, 3, 5) +
            _rec(_waveAudioHandler, 98, 100),
      );
      expect(failCode, 1);
      expect(failOut, allOf([...targets.map(contains), contains('3/5')]));

      final (emptyCode, emptyOut) = run('empty.info', '');
      expect(emptyCode, 1);
      expect(emptyOut, allOf([...targets.map(contains), contains('기록 없음')]));
    });
  });

  group('속성', () {
    kc.property('[P-GT-1] 실행 기록을 lcov 로 쓴 뒤 해석하면 줄 수가 기록에서 직접 센 값과 같다', () {
      // P-GT-1: 왕복 (줄을 빠뜨리거나 실행 횟수 0 을 실행으로 세면 실패)
      kc.forAll(_records(), (record) {
        expect(_entries(parseLcov(_writeLcov(record))), unorderedEquals(_counted(record)));
      });
    });

    kc.property('[P-GT-2] 대상이 아닌 파일의 기록을 더해도 대상별 결과와 전체 판정이 같다', () {
      // P-GT-2: 잡음 불변 (대상이 아닌 파일이 줄 수나 판정에 섞이면 실패)
      kc.forAll(_noiseCases(), (input) {
        final (targetLines, noises, threshold) = input;
        final targets = [for (var i = 0; i < targetLines.length; i++) 'lib/gen/t_$i.dart'];
        final chunks = [
          for (var i = 0; i < targets.length; i++)
            if (targetLines[i] != null) _chunk(targets[i], targetLines[i]!.entries),
        ];
        final withNoise = [...chunks];
        for (final (kind, index, lines, position) in noises) {
          final path = switch (kind) {
            0 => 'lib/noise/n_$index.dart',
            1 => 'test/n_${index}_test.dart',
            _ => '${targets[index % targets.length]}.orig',
          };
          withNoise.insert(position % (withNoise.length + 1), _chunk(path, lines.entries));
        }

        final before = evaluateCoverage(chunks.join(), targets: targets, thresholdPercent: threshold);
        final after = evaluateCoverage(withNoise.join(), targets: targets, thresholdPercent: threshold);

        // 양쪽이 모두 빈 결과여서 통과하는 일을 막는다.
        expect(before.targets, hasLength(targets.length));
        expect(after.targets, hasLength(targets.length));
        List<(String, int, int, bool, int)> rows(GateResult result) =>
            [for (final t in result.targets) (t.target, t.hitLines, t.totalLines, t.passed, t.missingLines)];
        expect(rows(after), rows(before));
        expect(after.passed, before.passed);
      });
    });

    kc.property('[P-GT-3] 전체 판정은 모든 대상이 기준을 채우고 전체 줄이 1 이상인 것과 같다', () {
      // P-GT-3: 판정식 (비교 방향 · 반올림 · 기록 없는 대상 처리가 다르면 실패)
      kc.forAll(kc.combine2(kc.list(_targetCounts(), minLength: 1, maxLength: 6), _thresholds()), (input) {
        final (counts, threshold) = input;
        final targets = [for (var i = 0; i < counts.length; i++) 'lib/gen/t_$i.dart'];
        final content = StringBuffer();
        for (var i = 0; i < counts.length; i++) {
          final (total, hit, sfOnly) = counts[i];
          if (total > 0 || sfOnly) content.write(_rec(targets[i], hit, total));
        }

        final result = evaluateCoverage(content.toString(), targets: targets, thresholdPercent: threshold);

        expect(result.targets, hasLength(targets.length));
        final expected = [for (final (total, hit, _) in counts) hit * 100 >= threshold * total && total > 0];
        expect([for (final target in result.targets) target.passed], expected);
        expect(result.passed, expected.every((passed) => passed));
      });
    });

    kc.property('[P-GT-4] 파일 기록의 순서를 섞거나 여러 덩어리로 나눠 써도 해석 결과가 같다', () {
      // P-GT-4: 순서 · 나누기 불변 (마지막 덩어리만 남기거나 덩어리마다 항목을 따로 만들면 실패)
      kc.forAll(kc.combine2(_records(), _choices()), (input) {
        final (record, choices) = input;
        final filesWithLines = record.values.where((lines) => lines.isNotEmpty).length;

        final standard = _entries(parseLcov(_writeLcov(record)));
        final varied = _entries(parseLcov(_writeSplitAndShuffled(record, choices)));

        // 양쪽이 모두 빈 결과여서 통과하는 일을 막는다.
        expect(standard, hasLength(filesWithLines));
        expect(varied, hasLength(filesWithLines));
        expect(varied, unorderedEquals(standard));
      });
    });

    kc.property('[P-GT-5] 모자란 줄 수만큼 더 실행하면 통과하고 하나 적으면 통과하지 못한다', () {
      // P-GT-5: 모자란 줄 수는 최소값 (하나 많거나 적게 계산하면 실패)
      kc.forAll(_failingTargets(), (input) {
        final (total, threshold, hit) = input;
        const target = 'lib/gen/t.dart';
        GateResult evaluateWithHit(int hitLines) =>
            evaluateCoverage(_rec(target, hitLines, total), targets: const [target], thresholdPercent: threshold);
        final reason = '$hit/$total, 기준값 $threshold';

        final result = evaluateWithHit(hit);
        expect(result.targets, hasLength(1), reason: reason);
        expect(result.targets[0].passed, isFalse, reason: reason);
        final missing = result.targets[0].missingLines;
        expect(missing, inInclusiveRange(1, total - hit), reason: reason);

        final enough = evaluateWithHit(hit + missing);
        expect(enough.targets, hasLength(1), reason: reason);
        expect(enough.targets[0].passed, isTrue, reason: '$reason, $missing줄 더 실행');
        expect(enough.passed, isTrue, reason: reason);

        final oneShort = evaluateWithHit(hit + missing - 1);
        expect(oneShort.targets, hasLength(1), reason: reason);
        expect(oneShort.targets[0].passed, isFalse, reason: '$reason, ${missing - 1}줄 더 실행');
      });
    });
  });
}
