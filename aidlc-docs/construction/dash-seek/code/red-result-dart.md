# RED 판정 표 (Dart) - dash-seek

실행: 2026-11-17, 브랜치 `feat/dash-seek`, 운영 코드는 뼈대 (`6aa9d69`) 그대로.

| 명령 | 결과 |
| --- | --- |
| `flutter test` (전체) | 345개 가운데 통과 301, 실패 44 |
| `flutter test test/features/player/dlna_backend_test.dart` | 108개 가운데 통과 67, 실패 41 |
| `flutter test test/core/native/tidal_sdk_native_bridge_test.dart` | 6개 가운데 통과 3, 실패 3 |
| `dart format --output=none --set-exit-if-changed --line-length 120 lib test tool` | 통과 |
| `flutter analyze --fatal-infos` | 통과 (No issues found) |

합계: RED 인정 44 (새 테스트 40 + 고친 기존 테스트 4), 보호 12 (새 테스트 11 + 고친 기존 테스트 1), 건드리지 않은 기존 테스트 289개는 모두 통과 (`dlna_backend_test.dart` 안 58개 포함). 실패 44개는 모두 기대값 비교 실패다. 테스트 쪽 오류 (컴파일 · 도우미 · 생성기 · 예외) 는 없다. skip 없음.

첫 실행에서 DB-51 테스트 4개가 테스트 쪽 예외 (`.single` 의 `Bad state: No element` 3개, null 확인 1개) 로 실패해, 호출 목록 전체를 비교하는 단언으로 고쳐 다시 실행했다.

## `test/core/native/tidal_sdk_native_bridge_test.dart`

| 테스트 | 결과 | 실패 종류 | 판정 |
| --- | --- | --- | --- |
| [NB-01] 시작 위치를 밀리초 정수 startPositionMs로 더해 보낸다 | FAILED | 기대값 비교 (인자 맵에 `startPositionMs` 없음) | RED |
| [NB-01] 시작 위치를 생략하면 startPositionMs는 0이다 | FAILED | 기대값 비교 (0 기대, null) | RED |
| [NB-02] 응답의 proxyUrl과 startOffsetMs를 주소와 시작 오프셋으로 돌려준다 | FAILED | 기대값 비교 (28초 기대, 0) | RED |
| [NB-02] startOffsetMs가 없거나 숫자가 아니면 시작 오프셋은 0이다 | 통과 | - | 보호 (뼈대가 항상 0 을 돌려줌) |
| [NB-03] 채널 오류면 주소는 빈 문자열, 시작 오프셋은 0이다 | 통과 | - | 보호 |
| [NB-03] 응답에 proxyUrl이 없으면 startOffsetMs가 있어도 주소는 빈 문자열, 시작 오프셋은 0이다 | 통과 | - | 보호 |

## `test/features/player/dlna_backend_test.dart`: 고친 기존 테스트

| 테스트 | 결과 | 실패 종류 | 판정 |
| --- | --- | --- | --- |
| [DB-05] 프록시 등록에 곡 ID, 스트림 주소, 스피커 주소, MIME을 넘긴다 | FAILED | 기대값 비교 (인자 맵에 `startPositionMs` 없음) | RED |
| [DB-12] DASH 스트림은 시작 위치가 있어도 Seek를 보내지 않고, 등록할 때 startPositionMs로 넘긴다 | FAILED | 기대값 비교 (30000 기대, null) | RED |
| [DB-13] 탐색 가능 여부는 처음에도, DASH 곡을 보낸 뒤에도, 단일 파일 곡을 보낸 뒤에도 가능이다 | FAILED | 기대값 비교 (true 기대, false) | RED |
| [DB-39] 스피커가 등록해 둔 다음 곡을 재생하기 시작하면 … | FAILED | 기대값 비교 (`canSeek` true 기대, false) | RED |
| [DB-45] 단일 파일 곡의 탐색은 초 단위 위치로 Seek를 보내고, 거부되어도 예외를 던지지 않는다 | 통과 | - | 보호 (단일 파일 곡의 동작은 그대로) |

## 새 테스트: 시작 위치

| 테스트 | 결과 | 실패 종류 | 판정 |
| --- | --- | --- | --- |
| [DB-50] DASH 곡은 시작 위치를 프록시 등록의 startPositionMs로 넘기고 Seek를 보내지 않는다 | FAILED | 기대값 비교 (인자 맵에 `startPositionMs` 없음) | RED |
| [DB-50] 등록 응답의 startOffsetMs를 그 곡의 시작 오프셋으로 기억한다 | FAILED | 기대값 비교 (`position(28/180)` 기대, `position(0/180)`) | RED |
| [DB-50] DASH 곡을 처음부터 재생하면 startPositionMs는 0이고 시작 오프셋도 0이다 | FAILED | 기대값 비교 (0 기대, null) | RED |
| [DB-50b] 단일 파일 곡은 startPositionMs를 0으로 보내고 재생 명령 뒤에 Seek를 보낸다 | FAILED | 기대값 비교 (0 기대, null) | RED |

## 새 테스트: DASH 곡의 탐색

| 테스트 | 결과 | 실패 종류 | 판정 |
| --- | --- | --- | --- |
| [DB-51] DASH 곡의 탐색은 같은 곡을 그 위치로 다시 등록한 뒤 새 주소로 재생 명령을 보낸다 | FAILED | 기대값 비교 (등록 호출 1개 기대, 없음) | RED |
| [DB-51] 탐색의 재생 명령에는 재생을 시작할 때와 같은 메타데이터를 보낸다 | FAILED | 기대값 비교 (메타데이터 기대, null) | RED |
| [DB-51] 탐색은 TIDAL API를 다시 부르지 않고 재생을 시작할 때 받은 스트림 정보를 쓴다 | FAILED | 기대값 비교 (등록 매니페스트 기대, 등록 없음) | RED |
| [DB-51, DB-39] 갭리스로 넘어간 곡이 DASH면 탐색은 그 곡을 다시 등록한다 | FAILED | 기대값 비교 (등록 1회 기대, 0회) | RED |
| [DB-45, DB-39] 갭리스로 넘어간 곡이 단일 파일이면 탐색은 Seek만 보낸다 | 통과 | - | 보호 |
| [DB-52] 탐색에 성공하면 곧바로 시작 오프셋 위치와 버퍼링을 알리고, 곡 시작은 다시 알리지 않는다 | FAILED | 기대값 비교 (이벤트 2개 기대, 없음) | RED |
| [DB-52] 탐색 뒤의 폴링은 응답의 startOffsetMs를 시작 오프셋으로 쓴다 | FAILED | 기대값 비교 (`position(40/180)` 기대, `position(0/180)`) | RED |
| [DB-52] 탐색 뒤에는 PLAYING을 아직 보지 못한 상태로 돌아간다 | FAILED | 기대값 비교 (폴링 계속 기대, `state(stopped)` 로 멈춤) | RED |
| [DB-52] 탐색 뒤에는 무응답 횟수를 0부터 다시 센다 | FAILED | 기대값 비교 (이벤트 없음 기대, `DLNA_UNREACHABLE`) | RED |
| [DB-52] 탐색 뒤의 마지막 위치는 시작 오프셋이다 | FAILED | 기대값 비교 (`ended(101)` 기대, `state(stopped)`) | RED |
| [DB-52] 탐색 뒤에는 위치 기준을 다시 정한다 | FAILED | 기대값 비교 (`position(65/180)` 기대, `position(5/180)`) | RED |
| [DB-53] 탐색의 프록시 등록이 실패하면 PROXY_FAILED 예외를 던지고 … | FAILED | 기대값 비교 (`PROXY_FAILED` 기대, 예외 없음) | RED |
| [DB-53] 탐색의 등록 응답에 주소가 없어도 PROXY_FAILED 예외를 던진다 | FAILED | 기대값 비교 (`PROXY_FAILED` 기대, 예외 없음) | RED |
| [DB-53b] 탐색의 재생 명령이 거부되면 기기 이름이 든 DLNA_PLAY_FAILED 예외를 던지고 … | FAILED | 기대값 비교 (`DLNA_PLAY_FAILED` 기대, 예외 없음) | RED |
| [DB-57] 일시정지 상태에서 탐색하면 재생 명령 뒤에 Pause를 보내고 정지로 알린다 | FAILED | 기대값 비교 (SOAP 4개 기대, `Seek`) | RED |
| [DB-57] 일시정지 뒤 재개했으면 탐색에 Pause를 보내지 않는다 | FAILED | 기대값 비교 (SOAP 3개 기대, `Seek`) | RED |
| [DB-57] 일시정지 뒤 새로 재생했으면 탐색에 Pause를 보내지 않는다 | FAILED | 기대값 비교 (SOAP 3개 기대, `Seek`) | RED |
| [DB-57] 일시정지가 거부됐으면 탐색에 Pause를 보내지 않는다 | FAILED | 기대값 비교 (SOAP 3개 기대, `Seek`) | RED |
| [DB-59] 다음 곡이 등록되어 있으면 탐색의 재생 명령 뒤에 같은 주소·메타데이터로 다시 등록한다 | FAILED | 기대값 비교 (SOAP 4개 기대, `Seek`) | RED |
| [DB-59] 다음 곡을 다시 등록하지 못하면 등록 정보를 지우되 … | FAILED | 기대값 비교 (SOAP 4개 기대, `Seek`) | RED |
| [DB-60] 연달아 탐색하면 두 번째의 등록과 스피커 명령은 첫 번째가 끝난 뒤에 시작한다 | FAILED | 기대값 비교 (첫 탐색 미완료 기대, 완료) | RED |
| [DB-60] 탐색이 진행 중이면 새 재생의 스피커 명령은 탐색이 끝난 뒤에 시작한다 | FAILED | 기대값 비교 (등록 [101] 기대, [102]) | RED |
| [DB-60] 탐색이 진행 중이면 다음 곡 등록은 탐색이 끝난 뒤에 실행된다 | FAILED | 기대값 비교 (등록 [101] 기대, [102]) | RED |
| [DB-61] 재생한 곡이 없을 때의 탐색은 Seek만 보낸다 | 통과 | - | 보호 |
| [DB-61] DASH 곡을 정지한 뒤의 탐색은 다시 등록하지 않고 Seek만 보낸다 | 통과 | - | 보호 |

## 새 테스트: 위치 보정

| 테스트 | 결과 | 실패 종류 | 판정 |
| --- | --- | --- | --- |
| [DB-54] 첫 RelTime으로 위치 기준을 정한다 (경계 표 7행) | FAILED | 기대값 비교 (2행: `position(17/180)` 기대, `position(7/180)`). 1행 (절대) 은 통과하고 첫 상대 행에서 멈춤 | RED |
| [DB-54] 상대로 정한 기준은 나중 RelTime이 오프셋을 넘어도 바꾸지 않는다 | FAILED | 기대값 비교 (`position(63/180)` 기대, `position(3/180)`) | RED |
| [DB-54] 절대로 정한 기준은 나중 RelTime이 작아져도 바꾸지 않는다 | 통과 | - | 보호 (절대 = 보정 없음. 구현 뒤 기준을 다시 판정하면 잡는다) |
| [DB-55] 위치 기준이 상대면 시작 오프셋(초 단위로 버림)에 RelTime을 더해 알린다 | FAILED | 기대값 비교 (33초 기대, 5초) | RED |
| [DB-55b] 위치 기준이 절대면 RelTime을 그대로 알린다 | 통과 | - | 보호 (구현 뒤 오프셋을 무조건 더하면 잡는다) |
| [DB-55c] 위치 기준이 정해지기 전(RelTime 0)에는 시작 오프셋을 알리고, … | FAILED | 기대값 비교 (`position(60/180)` 기대, `position(0/180)`) | RED |
| [DB-56] 시작 오프셋이 있는 흐름의 길이는 렌더러 값이 아니라 곡의 길이다 | FAILED | 기대값 비교 (`position(65/180)` 기대, `position(5/120)`) | RED |
| [DB-56] 시작 오프셋이 있는 흐름에서 곡의 길이를 모르면 길이 없이 알린다 | FAILED | 기대값 비교 (`position(65/-)` 기대, `position(5/120)`) | RED |
| [DB-56b] 곡 끝은 보정한 위치로 판정한다 | FAILED | 기대값 비교 (`ended(101)` 기대, `state(stopped)`) | RED |
| [DB-56b] 위치 기준이 절대면 오프셋을 더하지 않은 위치로 곡 끝을 판정한다 | 통과 | - | 보호 |
| [DB-56b] 멈춘 시점에 RelTime이 0이면 직전의 보정 위치로 판정한다 | FAILED | 기대값 비교 (`ended(101)` 기대, `state(stopped)`) | RED |
| [DB-58] 갭리스로 넘어가면 시작 오프셋이 0이 되어 새 곡의 위치와 길이를 그대로 알린다 | 통과 | - | 보호 (뼈대에는 오프셋이 없음) |
| [DB-58] 새로 재생하면 시작 오프셋이 0이 된다 | 통과 | - | 보호 |
| [DB-58] 새로 재생하면 위치 기준을 다시 정한다 | FAILED | 기대값 비교 (`position(65/180)` 기대, `position(5/180)`) | RED |

## 새 테스트: 속성

| 테스트 | 결과 | 실패 종류 | 판정 |
| --- | --- | --- | --- |
| [P-DB-6] 시작 오프셋이 있는 흐름의 위치는 첫 RelTime으로 정한 기준을 끝까지 따르고 줄어들지 않는다 | FAILED | 기대값 비교. 반례 `offset=3600s, rel=[3592, 3601, …]` (seed 20261117): O + `RelTime` 기대, `RelTime` 그대로 | RED |
| [P-DB-7] 어떤 시작 위치든 DASH 곡은 startPositionMs로만, 단일 파일 곡은 Seek로만 넘긴다 | FAILED | 기대값 비교. 반례 `dash start=0ms`: `startPositionMs` 0 기대, null | RED |

## 건드리지 않은 기존 테스트

`dlna_backend_test.dart` 의 나머지 58개 (DB-01 ~ DB-49 가운데 위 5개를 뺀 것, P-DB-1 ~ P-DB-5) 와 다른 테스트 파일 231개는 모두 통과했다. 커버리지 검사 (`test/tool/coverage_gate_test.dart`) 도 통과했다.

## 규칙별 새 테스트 수

| 규칙 | 새 테스트 | 규칙 | 새 테스트 |
| --- | --- | --- | --- |
| NB-01 | 2 | DB-55 | 1 |
| NB-02 | 2 | DB-55b | 1 |
| NB-03 | 2 | DB-55c | 1 |
| DB-50 | 3 | DB-56 | 2 |
| DB-50b | 1 | DB-56b | 3 |
| DB-51 | 4 (전환 뒤 1개 포함) | DB-57 | 4 |
| DB-45 (전환 뒤) | 1 | DB-58 | 3 |
| DB-52 | 6 | DB-59 | 2 |
| DB-53 | 2 | DB-60 | 3 |
| DB-53b | 1 | DB-61 | 2 |
| DB-54 | 3 (경계 표 1개 포함) | P-DB-6 · P-DB-7 | 2 |

새 테스트 51개 (NB 6, DB 43, 속성 2). 고친 기존 테스트 5개 (DB-05, DB-12, DB-13, DB-39, DB-45).
