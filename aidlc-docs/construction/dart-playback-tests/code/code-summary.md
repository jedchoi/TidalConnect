# 코드 요약 (Code Summary) - dart-playback-tests

작성일: 2026-11-17. 브랜치 `aidlc/test-reinforcement`. 계획: `aidlc-docs/construction/plans/dart-playback-tests-code-generation-plan.md` (Step 19개 모두 완료).

## 결과

| 항목 | 결과 |
| --- | --- |
| 새 테스트 | 167개 (예시 기반 147개 + 속성 20개). 전체 95개 → 262개 |
| 규칙 대응 | `business-rules.md` 의 규칙 127개 모두에 테스트가 있음 (테스트 이름의 `[PB-01]` 같은 표기로 대조) |
| 속성 대응 | `business-logic-model.md` 의 속성 18개 모두에 속성 테스트가 있음 |
| 커버리지 (NFR-01) | 대상 4개 파일 모두 98% 이상 (목표 80%). 아래 표 |
| 발견한 버그 (FR-08) | 없음 |
| 운영 코드 변경 | `lib/features/dlna/data/dlna_manager.dart` 1개 파일 (+8 −4 줄) |

### 커버리지

`flutter test --coverage` 기준 라인 커버리지.

| 파일 | 작업 전 | 작업 후 | 실행되지 않은 줄 |
| --- | --- | --- | --- |
| `lib/features/player/data/backends/phone_backend.dart` | 0% (0/61) | 100% (61/61) | 없음 |
| `lib/features/player/data/backends/dlna_backend.dart` | 0% (0/178) | 99.4% (177/178) | 313행: 주소를 URI 로 해석하지 못했을 때의 문자열 비교 |
| `lib/features/dlna/data/dlna_manager.dart` | 15.4% (20/130) | 99.2% (132/133) | 17행: 테스트용 생성자에서 탐색 서비스를 생략했을 때의 기본값 |
| `lib/features/player/data/wave_audio_handler.dart` | lcov 에 없음 | 98.7% (77/78) | 87행: 곡이 있다가 없어졌을 때 현재 곡 정보를 비우는 줄 |

## 파일

### 수정 (Modified)

| 파일 | 내용 |
| --- | --- |
| `lib/features/dlna/data/dlna_manager.dart` | `_soapClient` 를 생성자 초기화로 옮기고 `DlnaManager.forTesting` 에 `soapClient` 매개변수 추가. 운영 싱글톤 (`DlnaManager.instance`) 의 동작은 같다 |
| `pubspec.yaml`, `pubspec.lock` | `dev_dependencies` 에 `fake_async: ^1.3.0`, `kiri_check: ^1.4.0` 추가. `pubspec.lock` 은 개발용 간접 의존 31개가 바뀜 |
| `test/helpers/fakes.dart` | `FakeAuthRepository.validUserToken` 추가 (지정하지 않으면 기존 동작) |
| `test/helpers/app_overrides.dart` | `FakeApiClient` 에 `getPlaybackInfo` 결과 지정 · 호출 기록, `FakeSsdpDiscoveryService` 에 기기 목록 · 예외 · 응답 붙잡기 추가 (기본은 기존 동작) |
| `test/features/player/player_manager_test.dart` | `FakeBackend` 정의를 지우고 `test/helpers/fake_backend.dart` 를 import. 테스트 내용은 그대로 |
| `CLAUDE.md` | "Docs and references" 에 새 문서 2개를 가리키는 줄 추가 |

### 생성 (Created)

| 파일 | 내용 |
| --- | --- |
| `test/helpers/fake_native_channel.dart` | `FakeNativeChannel`: MethodChannel 가로채기, 호출 기록, 응답 · 실패 지정, 응답 붙잡기, 네이티브 → Dart 호출 |
| `test/helpers/fake_soap_client.dart` | `FakeSoapClient`: SOAP 액션 기록, 액션별 결과 · 예외, 폴링 응답 (고정값과 순서 목록), 응답 붙잡기 |
| `test/helpers/fake_backend.dart` | `FakeBackend`: `player_manager_test.dart` 에서 옮기고 명령 기록 추가 |
| `test/helpers/playback_fixtures.dart` | 곡 · 스피커 · 스트림 정보 생성 함수, `DlnaBackendHarness`, `capture` (가짜 시간 안에서 비동기 결과 받기), `throwsPlaybackException`, `muteDebugLogs` |
| `test/helpers/event_descriptions.dart` | `describeEvent`: `BackendEvent` 를 한 줄 문자열로 |
| `test/helpers/generators.dart` | 속성 테스트의 도메인 생성기 |
| `test/helpers/pbt_config.dart` | 고정 seed (20261117), `PBT_SEED` 환경 변수, 속성당 100회 |
| `test/features/player/phone_backend_test.dart` | 테스트 34개 + 속성 5개 (PB-01 ~ PB-26, P-PB-1 ~ P-PB-5) |
| `test/features/dlna/dlna_manager_test.dart` | 테스트 32개 + 속성 8개 (DM-01 ~ DM-29, P-DM-1 ~ P-DM-6) |
| `test/features/player/dlna_backend_test.dart` | 테스트 56개 + 속성 5개 (DB-01 ~ DB-49, P-DB-1 ~ P-DB-5) |
| `test/features/player/wave_audio_handler_test.dart` | 테스트 25개 + 속성 2개 (WA-01 ~ WA-23, P-WA-1 ~ P-WA-2) |
| `docs/failure-scenarios.md` | 실기기 장애 상황 점검표 7개 |
| `docs/incidents/README.md` | 문제 기록 절차와 양식 |

## 검증 결과 (계획 Step 18)

| # | 확인 | 명령 | 결과 |
| --- | --- | --- | --- |
| 18.1 | 포맷 | `dart format --output=none --set-exit-if-changed --line-length 120 lib test` | 통과 (87개 파일, 변경 0) |
| 18.2 | 정적 분석 | `flutter analyze --fatal-infos` | No issues found |
| 18.3 | 전체 테스트 | `flutter test` | 262개 통과, 실패 0 (기존 95개 포함) |
| 18.4 | 커버리지 | `flutter test --coverage` | 위 표 |
| 18.5 | 반복 실행 | 새 테스트 파일 4개를 10회 | 10회 모두 167개 통과 |
| 18.6 | 순서 무작위 | `--test-randomize-ordering-seed=random` | 새 테스트 파일 4개: 5회 모두 통과. 전체: 3회 중 2회 통과, 1회는 기존 테스트 1개가 실패 (아래 "알려 둘 점") |
| 18.7 | 실행 시간 | `flutter test` 3회 측정 | 기존 테스트만 4.4 ~ 5.3초 → 전체 5.6 ~ 9.0초. 증가 약 1 ~ 4초 (기준 30초) |
| 18.8 | 공통 점검 | `tool/check.sh --skip-android` | 모든 점검 통과 |
| 18.9 | 비밀 값 · 변경 범위 | `config/tidal.json` 값 검색, `git diff --stat main -- lib/` | 테스트 · 문서에 0건. 사설 대역 주소 없음. `lib/` 변경은 `dlna_manager.dart` 1개 |
| 18.10 | 복제 파일 | `*_new.*`, `*_modified.*`, `*_v2.*` 검색 | 없음 |

### 테스트가 잘못을 잡는지 확인 (변형 확인)

테스트가 처음부터 모두 통과했기 때문에, 운영 코드를 일부러 틀리게 바꿔 테스트가 실패하는지 확인하고 되돌렸다. 계획에는 없던 추가 확인이다.

| 대상 | 넣은 변형 | 감지 |
| --- | --- | --- |
| `PhoneBackend` | 5개 (STALLED 에서도 탐색, 정지 때 시작 위치 유지, 탐색 단위 초 등) | 5/5 |
| `DlnaManager` | 6개 (볼륨 범위 제한 없음, 재생 전 Stop 생략, 재생 중 선택 정리 등) | 6/6 |
| `DlnaBackend` | 10개 (곡 끝 허용치 10초, 무응답 한도 2회, 직렬화 없음, 늦은 응답 처리 등) | 10/10 |
| `WaveAudioHandler` | 11개 (버튼 조건 반대, 로컬 · 원격 반대, 볼륨 방향 등) | 11/11 |

## 발견한 것

### 버그 (FR-08): 없음

테스트가 규칙과 다르게 동작한 곳은 없었다. 수정한 운영 코드도 없다.

### 관찰 사항 추가: O-8

속성 P-DM-5 (같은 결과로 두 번 탐색해도 선택이 같다) 가 처음에 실패했다. 선택된 원격 스피커와 저장된 UDN 이 서로 다른 기기인 상태에서는 두 번째 탐색이 저장된 기기를 다시 고른다. 코드를 확인하니 선택은 `selectDevice` 와 탐색 뒤 정리로만 바뀌어 이 상태가 앱에서 생기지 않으므로, 버그가 아니라 생성 조건이 넓었던 것으로 판단했다. 생성 조건을 좁히고 `business-rules.md` 7절에 O-8 로 기록했다. 저장소 쓰기가 실패하는 경우에는 이 상태가 될 수 있으나 재현하지 않았다.

### 알려 둘 점: 기존 테스트 1개가 실행 순서에 의존한다

`test/core/theme/app_theme_test.dart` 는 `--test-randomize-ordering-seed=996956541` 로 실행하면 단독으로도 실패한다 (`google_fonts` 가 글꼴을 네트워크로 받으려다 실패). 이 파일은 이번 작업에서 바꾸지 않았고 `main` 과 같다. 기본 순서 (`flutter test`, `tool/check.sh`) 에서는 통과한다. 이번 unit 의 범위 밖이라 고치지 않았다.

## 계획과 달라진 점 (CG-7)

### 계획에 없던 변경

| 변경 | 이유 |
| --- | --- |
| `muteDebugLogs` 도우미 (새 테스트 파일 4개에서 앱 로그 출력을 끔) | 속성 테스트가 같은 흐름을 수백 번 실행해 로그 출력이 지나치게 많아진다. 기존 테스트의 출력은 그대로다 |
| `capture`, `CallResult`, `throwsPlaybackException` 도우미 | 가짜 시간 안에서는 `await` 할 수 없어 비동기 결과를 받아 둘 수단이 필요했다. 예외 코드 단언이 여러 파일에서 반복된다 |
| `FakeSoapClient.throwing`, `FakeSsdpDiscoveryService.error` | SOAP 예외 (DM-10) 와 탐색 예외 (DM-23) 규칙을 검증하는 데 필요했다 |
| 변형 확인 (위 표) | 테스트가 처음부터 모두 통과해, 실제로 잘못을 잡는지 확인이 필요했다. 운영 코드는 매번 되돌렸다 |
| 속성 테스트가 20개 (속성은 18개) | P-DM-4, P-DM-5 는 내용이 두 부분이라 테스트를 둘로 나눴고, P-DB-1 · P-DB-2 는 한 테스트에서 함께 검증하되 길이를 아는 곡과 모르는 곡으로 두 번 실행한다 |
| 설계 문서 커밋 3개 (NFR Requirements, NFR Design, 코드 생성 계획) | 코드 커밋과 섞이지 않도록 코드 생성 전에 먼저 커밋했다 |

### 계획에서 뺀 항목

없음.

### 설계에서 정한 대안을 쓰지 않은 것

- `fake_async` 안에서 가짜 채널 응답이 정상 완료되어 (Step 5), 폴링 간격 주입 (Application Design 계획 Q3 의 B) 은 필요 없었다
- `kiri_check` 의 상태 기반 테스트 API 는 쓰지 않았다. 응답 목록을 생성해 `forAll` 안에서 모델과 한 단계씩 비교했다 (`tech-stack-decisions.md` D1 의 대안, PBT-06 요건은 충족)
- 속성당 실행 횟수는 100회 그대로다 (시간 기준 안)

## 커밋

| 커밋 | 내용 |
| --- | --- |
| `132ba20` | test: 재생 · DLNA 테스트용 fake 와 도우미 추가 |
| `d0f4c2a` | test: PhoneBackend 명령 · 이벤트 변환 테스트 추가 |
| `afd0b9d` | test: DlnaManager 명령 전달 · 선택 정리 테스트 추가 |
| `1778c4f` | test: DlnaBackend 재생 · 폴링 · 갭리스 테스트 추가 |
| `8c85b0d` | test: WaveAudioHandler 명령 전달 · 상태 알림 테스트 추가 |
| `9404a15` | docs: 실기기 장애 상황 점검표와 문제 기록 절차 추가 |

그 앞에 설계 문서 커밋 3개 (`5b0eb01`, `5ceabf3`, `32c78e7`), 그 뒤에 이 요약을 담은 커밋이 있다. 푸시하지 않았다.

## 확장 규칙 준수

### Property-Based Testing

| 규칙 | 상태 | 근거 |
| --- | --- | --- |
| PBT-01 | compliant | 속성 18개가 모두 구현됨 |
| PBT-02 | compliant | P-DM-1 (초 ↔ 시간 문자열 왕복) |
| PBT-03 | compliant | P-PB-1 · 3 · 4, P-DM-2 · 4 · 6, P-DB-2 ~ 5, P-WA-1 · 2 |
| PBT-04 | compliant | P-DM-5 (선택 · 탐색의 멱등성) |
| PBT-05 | compliant | P-PB-2, P-DM-3 (참조 식과 비교) |
| PBT-06 | compliant | P-PB-5, P-DB-1 은 모델 (`PendingSeekModel`, `PollModel`) 과 명령마다 비교. 길이 0 인 순서 포함. `DlnaManager` 의 선택 정리는 P-DM-6 의 불변 조건으로 검증 |
| PBT-07 | compliant | `test/helpers/generators.dart` 한곳에 도메인 생성기. 범위는 `domain-entities.md` 3절 |
| PBT-08 | compliant | 축소 설정을 바꾸지 않음. 고정 seed. 실패 시 `Falsifying example: ... (seed N)` 출력을 확인함. 일반 `flutter test` 에 포함 |
| PBT-09 | compliant | `kiri_check` 가 `pubspec.yaml` 의 `dev_dependencies` 에 있음 |
| PBT-10 | compliant | 규칙마다 예시 기반 테스트가 있고 속성은 그 위에 더함 |

### Resiliency

| 규칙 | 상태 | 근거 |
| --- | --- | --- |
| RESILIENCY-14 | compliant | 자동 테스트가 장애 동작 6가지를 고정 (`nfr-design-patterns.md` RS-1), `docs/failure-scenarios.md` 작성 |
| RESILIENCY-15 | compliant | `docs/incidents/README.md` 작성 |
| 그 밖 | N/A | 운영 경로에 새 외부 호출 · 저장소 · 배포 구성 없음 |

## 사용법 메모

- 속성 테스트 실패를 재현: 출력된 seed 로 `PBT_SEED=<seed> flutter test <파일>`
- 다른 입력 탐색: `PBT_SEED=$RANDOM flutter test`
- 커버리지 측정: `flutter test --coverage` (`coverage/lcov.info` 가 생긴다. `.gitignore` 에 `coverage/` 가 아직 없으므로 커밋하지 않게 주의. `ci-quality-gate` unit 에서 추가 예정)
