# REFACTOR 후보 표 - ci-quality-gate (Step 5.1)

GREEN 커밋 `168f2f0` 과 Step 4 (연결) 뒤의 상태에서 찾은 후보다. **아직 적용하지 않았다.** 사람 승인 (관문 3) 뒤에 승인된 것만 적용한다.

- 기준: 테스트가 동작 명세다. 테스트 변경 0 (`git diff --exit-code 7d9ad11 -- test/tool`), 결과 동일
- 찾은 범위: 이 unit 에서 바꾼 파일 (`tool/coverage_gate.dart`, `tool/check.sh`, `.github/workflows/check.yml`, `CLAUDE.md`, `README.md`)
- 시작 상태: `flutter test` 284개 통과, 포맷 · 분석 통과, 대상 4개 커버리지 98.7 ~ 100.0%

## 후보

| 번호 | 후보 | 위치 | 이유 | 동작 변화 위험 | 권고 |
| --- | --- | --- | --- | --- | --- |
| R1 | 폭 계산 `fold` 두 개를 `dart:math` 의 `max` 로 바꾼다 | `coverage_gate.dart` `formatReport` | 같은 꼴의 삼항식이 두 번 나온다. `max` 를 쓰면 "가장 긴 값의 길이" 라는 뜻이 바로 읽힌다. `dart:math` 는 순수 Dart 라 Flutter 없이 실행된다 | 낮음. 출력 글자가 같아야 한다 (줄 맞춤은 테스트가 보지 않으므로 실제 출력을 앞뒤로 비교) | 적용 |
| R2 | 비율 칸 폭 `9` 를 이름 있는 상수로 뺀다 | `coverage_gate.dart` `formatReport` | 숫자의 뜻 (`기록 없음` 의 화면 폭) 이 주석에만 있다 | 낮음. 값은 그대로 | 적용 |
| R3 | 기본 경로 `'coverage/lcov.info'` 를 파일 위쪽 상수로 올린다 | `coverage_gate.dart` `runCoverageGate` | 대상 · 기준값과 함께 "바꿀 수 있는 값" 이 한곳에 모인다 (NFR-01-C6 의 취지. 요구 자체는 대상 · 기준값뿐이다) | 낮음. 공개 이름이 하나 늘지 않도록 비공개 상수로 둔다 | 적용 |
| R4 | 경로 비교를 `_matchesTarget(path, target)` 으로 뺀다 | `coverage_gate.dart` `evaluateCoverage` | GT-04 규칙이 이름과 문서 주석을 갖는다. 루프 안의 조건이 짧아진다 | 낮음. 식은 그대로 옮긴다 | 적용 |
| R5 | `DA:` 한 줄을 합칠 때 원소 하나짜리 맵을 만들지 않게 한다 (줄 하나를 합치는 함수를 두고 `_mergeLineHits` 가 그것을 쓴다) | `coverage_gate.dart` `_parseLineHits`, `_mergeLineHits` | 줄마다 임시 맵을 만드는 것은 합치는 함수의 모양에 맞추느라 생긴 우회다 | 낮음. GT-02 · P-GT-4 가 합치기를 잡는다 | 적용 |
| R6 | 대상 하나의 판정 (통과식 · 모자란 줄 수) 을 `(hit, total, threshold)` 를 받는 함수로 뗀다 | `coverage_gate.dart` `evaluateCoverage` | 루프가 짧아진다 | 낮음 | 그대로 둠. R4 를 적용하면 루프가 20줄 안쪽이고, GT-05 · GT-06 · GT-10 이 한 화면에 이어 보이는 쪽이 읽기 쉽다. 떼면 값 3개를 돌려줄 타입이나 레코드가 새로 필요하다 |
| R7 | `counts` 목록과 `result.targets` 를 인덱스로 맞추는 대신 한 번에 줄 항목을 만든다 | `coverage_gate.dart` `formatReport` | 목록 두 개를 인덱스로 맞춘다 | 낮음 | 그대로 둠. 폭을 먼저 구해야 해서 두 번 도는 구조는 남는다. 바꿔도 줄어드는 것이 없다 |
| R8 | README 의 대상 파일 4개 이름이 `coverageTargets` 와 겹친다 | `README.md` "점검" 절 | 대상이 바뀌면 두 곳을 고쳐야 한다 | 없음 (문서) | 그대로 둠. FR-09-C8 의 안내 문구이고, `CLAUDE.md` 는 상수 위치만 가리키게 했다. 대상은 4개로 고정이다 (결정 C3) |

`tool/check.sh` 와 `.github/workflows/check.yml` 은 **대상 없음**. JDK 탐색은 함수 하나 (`find_jdk`) 이고 중복이 없다. workflow 는 step 두 개를 더한 것뿐이다.

## 적용 순서와 커밋 단위

후보 하나에 커밋 하나. 순서는 서로 닿지 않는 것부터, `formatReport` → `runCoverageGate` → `evaluateCoverage` → 해석 순이다.

| 순서 | 후보 | 커밋 메시지 (안) |
| --- | --- | --- |
| 1 | R1 | `refactor: 커버리지 보고서의 폭 계산에 max 사용` |
| 2 | R2 | `refactor: 커버리지 보고서의 비율 칸 폭을 상수로 분리` |
| 3 | R3 | `refactor: 커버리지 검사의 기본 lcov 경로를 상수로 분리` |
| 4 | R4 | `refactor: 커버리지 대상 경로 비교를 함수로 분리` |
| 5 | R5 | `refactor: lcov 줄 기록 합치기를 줄 단위 함수로 정리` |

후보마다 확인할 것:

1. `flutter test test/tool/coverage_gate_test.dart` 22개 통과, `flutter test` 284개 통과
2. `dart format --output=none --set-exit-if-changed --line-length 120 lib test tool`, `flutter analyze --fatal-infos`
3. `git diff --exit-code 7d9ad11 -- test/tool` 차이 없음
4. `dart tool/coverage_gate.dart` 의 출력이 적용 전과 글자 단위로 같음 (줄 맞춤은 테스트가 보지 않는다). 실패 · 기록 없음 줄이 있는 lcov 로도 한 번 비교한다

실패하면 그 후보만 되돌리고 원인을 보고한다.

## 바꾸지 않는 것

- 공개 이름 (`coverageTargets`, `coverageThresholdPercent`, 타입 3개, 함수 4개) 과 시그니처
- 보고서의 글자 (칸 순서, 간격, `전체 통과 (기준 80%)`), 안내 문구, 종료 코드
- 테스트 (`test/tool`), `tool/check.sh`, workflow, 문서
