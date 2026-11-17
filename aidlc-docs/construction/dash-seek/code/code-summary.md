# 코드 요약 (Code Summary) - dash-seek

작성일: 2026-11-17. 브랜치 `feat/dash-seek` (`main` 의 `f1f1fe1` 에서 시작, 푸시하지 않음). 계획: `aidlc-docs/construction/plans/dash-seek-code-generation-plan.md`. Build and Test 의 결과도 이 문서에 함께 적는다.

## 결과

| 항목 | 결과 |
| --- | --- |
| 기능 | DLNA 스피커에서 DASH 곡의 탐색, 중간 위치에서 시작 (출력 기기 전환 때 이어 재생) |
| 방식 | 요청한 위치가 속한 세그먼트부터의 흐름을 프록시에 새 주소로 등록하고 스피커에 다시 재생시킨다. 앱이 시작 오프셋으로 재생 위치를 보정한다 |
| 테스트 | Dart 284 → 342개, Kotlin 86 → 109개. 모두 통과 |
| 커버리지 | `dlna_backend.dart` 99.1% (235/237). 대상 4개 모두 기준 통과 |
| 점검 | `tool/check.sh` 전체 통과. debug APK 빌드 성공, 연결된 폰 (SM-F711N) 에 설치 (`7bf05a8`) |
| **실제 스피커에서의 동작** | 자동 테스트로는 확인되지 않는다. 2026-11-17 사용자가 폰에 설치해 써 본 뒤 "좋아 만족스러워" 로 확인. 어느 스피커에서 어느 항목을 해 봤는지는 기록되지 않아 `docs/dlna-compat.md` 의 "DASH 탐색" 열은 채우지 않았다 |

## 진행 방식

사용자 지시에 따라 모든 stage 와 TDD 의 사람 관문 (테스트 경계 표, RED 판정, 리팩토링 후보) 을 권장안으로 자동 승인했다. 단계마다 에이전트를 나누는 방식은 앞 작업과 같다: RED 2개 (Kotlin, Dart), GREEN · REFACTOR 2개 (Kotlin, Dart), 주 세션은 조율 · 확인 · 커밋.

구현 에이전트가 테스트가 보지 못한 위험을 두 번 찾아, 규칙을 추가하고 RED → GREEN 을 두 번 더 돌았다 (DB-62, DB-62c). 그래서 테스트 고정 커밋이 셋이다: `375ca35`, `bc9dfed`, `7d41b2b`.

## 바뀐 파일

### Kotlin 운영 (`android/app/src/main/kotlin/com/example/tidal_connect_lite/`)

| 파일 | 내용 |
| --- | --- |
| `DashManifest.kt` | `timescale` 과 세그먼트 길이로 시작 시각 계산. `segmentStartMs`, `segmentIndexAt` |
| `DashSegmentInputStream.kt` | 시작 세그먼트를 받아 초기화 세그먼트 + 그 번호부터 읽음 |
| `TidalStreamProxyServer.kt` | `registerTrackStreamAt` (주소와 시작 오프셋 반환). 길이는 "초기화 + 시작 세그먼트부터" 의 합. 길이 기억을 매니페스트 합계에서 세그먼트별로 바꿔, 같은 곡을 다른 위치로 다시 등록해도 다시 조회하지 않는다. 기존 `registerTrackStream` 은 그대로 남음 |
| `PlaybackContracts.kt` | `RegisteredStream`, `ProxyRegistrar` 에 `startPositionMs` |
| `PlaybackCommandRouter.kt` | 채널 `registerTrackStream` 이 `startPositionMs` 를 읽고 `{proxyUrl, startOffsetMs}` 를 돌려줌 |
| `PlaybackCore.kt` | `proxyRegistrar` 가 `registerTrackStreamAt` 을 부름 |

### Dart 운영

| 파일 | 내용 |
| --- | --- |
| `lib/core/native/tidal_sdk_native_bridge.dart` | `registerTrackStream(startPosition:)`, 반환 타입 `ProxyRegistration(url, startOffset)` |
| `lib/features/player/data/backends/dlna_backend.dart` | `canSeek` 항상 true. DASH 곡의 시작 위치는 등록 인자로. DASH 곡의 탐색 = 다시 등록 + 재생 명령 (다음 곡 등록 복원, 일시정지 유지). 시작 오프셋으로 위치 보정 (상대 · 절대 판정). 탐색 중에는 폴링을 건너뛰고 늦게 온 응답을 버림 |
| `lib/features/player/data/backends/playback_backend.dart` | `canSeek` 문서 주석 |

`PlayerManager`, `WaveAudioHandler`, 화면, `DlnaManager` 는 바꾸지 않았다. `canSeek` 이 true 가 되어 재생 화면과 잠금화면의 탐색이 기존 코드로 열린다.

### 테스트

| 파일 | 내용 |
| --- | --- |
| `DashManifestTest.kt` | DS-01 ~ 05, P-DS-1 · 2 추가 (기존 4개 그대로) |
| `TidalStreamProxyServerTest.kt`, `ProxyFixture.kt`, `ProxyGenerators.kt`, `DashGenerators.kt` (새 파일) | PS-01 ~ 10, P-PS-1 |
| `PlaybackCommandRouterTest.kt`, `RouterFakes.kt`, `RouterGenerators.kt` | CR-14 ~ 17 추가, 등록 관련 기존 테스트 8개를 새 규칙에 맞게 수정 |
| `test/features/player/dlna_backend_test.dart`, `test/helpers/` | DB-50 ~ 62c, P-DB-6 · 7 추가. 규칙이 바뀐 기존 테스트 5개 수정 (DB-05 · 12 · 13 · 39 · 45) |
| `test/core/native/tidal_sdk_native_bridge_test.dart` (새 파일) | NB-01 ~ 03 |

### 문서

`README.md` (알려진 제약 문구), `CLAUDE.md` (DASH 경로), `docs/dlna-compat.md` ("DASH 탐색" 확인 항목과 열), `docs/failure-scenarios.md` (항목 8, 9).

## RED · GREEN · REFACTOR

| 단계 | 결과 |
| --- | --- |
| RED 1 (`375ca35`) | Kotlin 새 테스트 23 + 수정 8: 19개 실패. Dart 새 테스트 51 + 수정 5: 44개 실패. 테스트 쪽 오류 0 |
| GREEN 1 | Kotlin `09a313a` (109개 통과), Dart `040f37d` (335개 통과) |
| RED 2 (`bc9dfed`) → GREEN (`6393cbe`) | DB-62 · 62b: 탐색이 진행 중이면 폴링 차례를 건너뜀. 테스트 5개 |
| RED 3 (`7d41b2b`) → GREEN (`7bf05a8`) | DB-62c: 탐색 전에 보낸 조회의 응답이 탐색 도중 도착하면 버림. 테스트 2개 |
| REFACTOR Kotlin | 적용 3 (`6c7113b` import 정리, `d46222c` 쓰지 않는 인자 제거, `3be73f1` KDoc 위치). 그대로 둠 5 (길이 조회 분리, 해석 결과 보관, 이진 탐색, 캐시 크기 제한 등) |
| REFACTOR Dart | 적용 4 (`1867ef2` 메타데이터 조립, `934bc5f` 등록 인자 조립, `93c2e22` 흐름 초기화, `5940c67` 탐색 본문 나누기). 그대로 둠 5 (값 객체로 묶기, 위치 기준 enum 등) |

규칙 문서의 "규칙 보완" 표 2개와 DB-62 · 62c 는 에이전트들이 빠졌다고 보고한 곳을 정한 것이다.

## 검증 (계획 Step 6, Build and Test)

| 확인 | 결과 |
| --- | --- |
| `tool/check.sh` 전체 (`JAVA_HOME` 없이) | 통과. Dart 342개, 커버리지 검사, Kotlin 109개 |
| 포맷, `flutter analyze --fatal-infos` | 통과 |
| 규칙 ID 대조 | DS · PS · CR-14 ~ 17 · NB · DB-50 ~ 62c · 속성 5개가 모두 테스트 이름에 있음 |
| 테스트 고정 | `git diff --exit-code 7d41b2b -- test` 와 `375ca35 -- android/app/src/test` 모두 차이 없음 |
| debug APK (키 포함) | 빌드 성공, 연결된 폰에 설치 |
| 변형 확인 (6.3), 새 테스트 10회 반복 (6.4) | **하지 않음.** 사용자 지시 ("반복테스트는 이제 그만하자") |

Kotlin 프록시 테스트의 간헐 실패: 구현 뒤 전체를 60회 반복하던 중 사용자 지시로 이후의 반복을 그만두었다. 그 60회에서는 3회 실패했는데, 2회는 같은 시간에 Dart 파일을 바꿔 가며 커밋한 탓의 컴파일 실패이고 1회가 `PX-38` 의 시간 초과다. 이번 변경으로 없어지지 않았다. 구현 에이전트의 추정 (길이를 모르는 세그먼트를 만났을 때 진행 중인 요청을 강제로 끊던 것이 원인) 은 확인되지 않았다.

## 실기기에서 확인할 것

자동 테스트는 "앱이 스피커에 무엇을 보내는지" 와 "프록시가 무엇을 응답하는지" 까지만 본다. 스피커가 그것을 받아 어떻게 동작하는지는 확인되지 않았다. 결과는 `docs/dlna-compat.md` 의 "DASH 탐색" 열에 적는다.

| # | 해 볼 것 | 볼 것 |
| --- | --- | --- |
| 1 | 스피커로 DASH 곡을 재생하다가 진행 막대로 위치를 옮긴다 | 그 근처에서 재생이 이어지는가 (중간 세그먼트부터의 흐름을 스피커가 재생하는가) |
| 2 | 옮긴 뒤 진행 막대의 위치 | 곡 전체 기준으로 맞는가. 설정 탭 디버그 로그의 `DLNA_BACKEND` 태그 "위치 기준: 절대 / 상대" 가 실제와 맞는가. 맞지 않으면 위치가 두 배로 가거나 옮긴 만큼 모자라게 보인다 |
| 3 | 폰에서 듣다가 스피커로 바꾼다 | 듣던 위치 근처에서 이어지는가 |
| 4 | 곡 끝 가까이로 옮겼다가 다시 중간으로 옮긴다 | 옮기는 도중에 다음 곡으로 넘어가거나 정지로 바뀌지 않는가 |
| 5 | 일시정지한 채 위치를 옮긴다 | 일시정지가 유지되는가 (재생 명령 직후의 일시정지 명령을 스피커가 받는가) |
| 6 | 탐색한 뒤 곡이 끝날 때 | 다음 곡으로 넘어가는가 (갭리스를 지원하는 스피커면 끊김 없이) |

알려진 한계:

- 탐색 단위가 세그먼트라 요청한 위치보다 몇 초 앞에서 시작한다. 옮길 때 짧게 끊긴다
- 시작 오프셋이 10초 미만이면 항상 "상대" 로 본다. 곡 전체 기준으로 알려 주는 스피커에서는 표시가 최대 10초쯤 앞설 수 있다
- 새 흐름을 재생하지 못하는 스피커에서는 오류 안내 없이 "버퍼링" 으로 남는다 (새 재생도 원래 같은 성질이다)
- 탐색의 재생 명령이 거부되면 스피커는 멈춘 상태가 되고, 곡 끝 3초 안에서 실패했다면 다음 곡으로 넘어간다
- 오래 일시정지한 뒤 탐색하면 세그먼트 주소가 만료되었을 수 있다 (DASH 세그먼트의 재발급은 전부터 없다)
- 길이를 모르는 세그먼트가 섞인 곡은 첫 응답까지의 시간이 전보다 길어질 수 있다 (조회한 것을 모두 기다려 아는 길이를 기억하도록 바뀜)

## 계획과 달라진 점

| 변경 | 이유 |
| --- | --- |
| RED → GREEN 을 두 번 더 돎 (DB-62, DB-62c) | 구현 에이전트가 탐색 중 폴링이 곡 종료로 오판할 수 있음을 발견 |
| 변형 확인과 10회 반복을 하지 않음 | 사용자 지시 |
| Build and Test 를 따로 문서로 만들지 않고 이 요약에 적음 | 빠른 진행 지시. 빌드 · 테스트 방법은 앞 작업의 `aidlc-docs/construction/build-and-test/` 안내서와 같다 |

## 확장 규칙 준수

- PBT: 새 속성 5개 (P-DS-1 · 2 불변 · 왕복, P-PS-1 왕복, P-DB-6 · 7 불변) 와 넓힌 P-CR-5. 고정 seed, 예시 기반 테스트와 병행. PBT-04 ~ 06 은 해당 없음 (새 멱등 연산 · 참조 구현 · 상태 기계 없음)
- Resiliency: RESILIENCY-14 (탐색 실패 · 등록 실패의 동작을 테스트로 고정, `docs/failure-scenarios.md` 에 항목 추가). 그 밖은 해당 없음
