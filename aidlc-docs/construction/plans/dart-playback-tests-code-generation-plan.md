# Code Generation 계획 - dart-playback-tests

**이 계획이 Code Generation 의 유일한 기준이다.** Part 2 (생성) 는 아래 Step 을 순서대로 실행하고, 끝낸 Step 을 바로 `[x]` 로 표시한다. 계획에 없는 변경이 필요해지면 멈추고 이유를 요약에 적는다.

## unit 맥락

| 항목 | 내용 |
| --- | --- |
| workspace 루트 | `/Volumes/Mac990/Project/TidalConnect` (Brownfield, 기존 구조 `lib/` · `test/` 사용) |
| 구현하는 요구사항 | FR-01, FR-02, FR-03, FR-04, FR-07 (Dart 부분), FR-08 (이 범위에서 발견한 것). 스토리가 없어 FR 과 규칙 ID (`business-rules.md`) · 속성 ID (`business-logic-model.md`) 로 추적한다 |
| 다른 unit 에 대한 의존 | 없음. `android-native-tests` 와 채널 계약 문자열을 공유하지만 코드 의존은 없다 |
| 인터페이스 · 계약 | MethodChannel `com.example.tidal_connect_lite/tidal_sdk` 의 메서드 이름 · 인자 키 (`api-documentation.md` C절). 바꾸지 않고 검증만 한다 |
| 소유하는 데이터베이스 엔티티 | 없음 |
| 경계 | 운영 코드 변경은 `lib/features/dlna/data/dlna_manager.dart` 의 생성자 초기화 1곳. 그 밖의 `lib/` 변경은 FR-08 버그 수정뿐이며 별도 커밋으로 한다 |
| 적용 설계 | 패턴 DT · VF · PT · AS · RS (`nfr-design-patterns.md`), 구성 요소 (`logical-components.md`), 결정 D1 ~ D8 (`tech-stack-decisions.md`) |

## 커밋

브랜치 `aidlc/test-reinforcement` 에 아래 "커밋" 표시 지점마다 로컬 커밋을 만든다 (푸시하지 않음). 이 계획의 승인을 그 커밋들에 대한 승인으로 본다. 커밋 메시지는 기존 방식 (`test: ...`, `fix: ...`, `docs: ...`, 한국어) 을 따른다.

## 실행 단계

### 준비

- [x] **Step 1. 의존성 추가** (NFR-02-D3, NFR-04, PBT-09, 결정 D1 · D2)
  - [x] 1.1 `pubspec.yaml` 의 `dev_dependencies` 에 `fake_async: ^1.3.0`, `kiri_check: ^1.4.0` 추가
  - [x] 1.2 `flutter pub get` 실행, `pubspec.lock` 갱신 확인
  - [x] 1.3 `flutter analyze --fatal-infos` 와 기존 테스트 95개 통과 확인

- [x] **Step 2. 운영 코드 대체 지점** (FR-07, `component-methods.md` 1절)
  - [x] 2.1 `lib/features/dlna/data/dlna_manager.dart`: `_soapClient` 를 생성자 초기화로 옮기고 `DlnaManager.forTesting` 에 `soapClient` 매개변수 추가 (기존 파일 수정)
  - [x] 2.2 기존 테스트 95개 통과 확인

- [x] **Step 3. fake** (FR-07, 패턴 DT-5 · VF-2 · AS-3)
  - [x] 3.1 `test/helpers/fake_native_channel.dart` 새로 만듦: `FakeNativeChannel` (가로채기 설치 · 해제, 호출 기록, 메서드별 응답 · 실패, 응답 붙잡기, 네이티브 → Dart 호출)
  - [x] 3.2 `test/helpers/fake_soap_client.dart` 새로 만듦: `FakeSoapClient` (액션 기록, 액션별 결과, 상태 · 위치 · 볼륨 응답의 고정값과 순서 목록, 응답 붙잡기)
  - [x] 3.3 `test/helpers/fake_backend.dart` 새로 만듦: `test/features/player/player_manager_test.dart` 의 `FakeBackend` 를 옮기고 `pause` · `resume` · `seek` · `stop` 호출 기록 추가. `player_manager_test.dart` 는 클래스 정의를 지우고 import 만 바꿈
  - [x] 3.4 `test/helpers/fakes.dart` 수정: `FakeAuthRepository` 에 사용자 토큰 결과 지정 (기본값은 기존 동작)
  - [x] 3.5 `test/helpers/app_overrides.dart` 수정: `FakeApiClient` 에 `getPlaybackInfo` 결과 지정 · 호출 기록 · 응답 붙잡기, `FakeSsdpDiscoveryService` 에 기기 목록 지정 · `onDeviceFound` 호출 · 응답 붙잡기 (기본값은 기존 동작)
  - [x] 3.6 기존 테스트 95개 통과 확인 (NFR-02-D2, NFR-05-D2)

- [x] **Step 4. 패턴 도우미** (패턴 AS-1 · AS-2 · VF-1 · PT-1 · PT-2)
  - [x] 4.1 `test/helpers/playback_fixtures.dart` 새로 만듦: 곡 · 원격 기기 · 스트림 정보 (단일 파일 / DASH) 생성 함수, 원격 스피커가 선택된 `DlnaManager` 생성 함수, `DlnaBackend` 테스트 묶음. 가짜 값 규칙 (`192.0.2.x`, `.test`) 적용
  - [x] 4.2 `test/helpers/event_descriptions.dart` 새로 만듦: `describeEvent`
  - [x] 4.3 `test/helpers/pbt_config.dart` 새로 만듦: 고정 seed, `PBT_SEED` 환경 변수, 실행 횟수 100
  - [x] 4.4 `test/helpers/generators.dart` 새로 만듦: `domain-entities.md` 3절의 생성기 (순서 생성기의 길이는 0 부터, PT-3)

- [x] **Step 5. 기술 위험 확인** (`application-design.md` 6절, 패턴 DT-1)
  - [x] 5.1 `test/features/player/dlna_backend_test.dart` 새로 만듦: 첫 테스트 `[DB-07]` 성공 흐름을 `fakeAsync` + `FakeNativeChannel` 로 작성
  - [x] 5.2 통과하면 계속. 가짜 채널 응답이 `fakeAsync` 안에서 완료되지 않으면 **여기서 멈추고** Application Design 계획 Q3 을 B (폴링 간격 주입) 로 바꾸는 변경을 요청
  - [x] 5.3 `kiri_check` 를 `flutter_test` · `fake_async` 와 함께 import 해 속성 하나 (`[P-DM-2]`, Step 9 에서 완성) 가 실행되는지 확인. 이름이 충돌하면 `hide` 또는 접두어 사용
  - [x] 커밋: `test: 재생 · DLNA 테스트용 fake 와 도우미 추가` (Step 1 ~ 5 의 의존성 · 대체 지점 · 도우미)

### `PhoneBackend` (FR-01)

- [x] **Step 6. `test/features/player/phone_backend_test.dart` 예시 기반 테스트** (새로 만듦)
  - [x] 6.1 명령 → 채널 호출: PB-01 ~ PB-10
  - [x] 6.2 재생 시작 뒤 탐색: PB-11 ~ PB-15
  - [x] 6.3 이벤트 변환: PB-16 ~ PB-24
  - [x] 6.4 스트림 오류 · 정리: PB-25, PB-26
- [x] **Step 7. `phone_backend_test.dart` 속성 테스트** (PBT-03 · 05 · 06)
  - [x] 7.1 P-PB-1 (이벤트 수), P-PB-2 (상태 대응, 오라클), P-PB-3 (위치), P-PB-4 (`transition`)
  - [x] 7.2 P-PB-5 (pending seek, 모델 비교): 테스트 파일 안에 모델 작성
  - [x] 커밋: `test: PhoneBackend 명령 · 이벤트 변환 테스트 추가`

### `DlnaManager` (FR-03)

- [x] **Step 8. `test/features/dlna/dlna_manager_test.dart` 예시 기반 테스트** (새로 만듦)
  - [x] 8.1 제어 URL 선택: DM-01 ~ DM-06
  - [x] 8.2 명령 전달: DM-07 ~ DM-18
  - [x] 8.3 탐색과 선택: DM-19 ~ DM-29
- [x] **Step 9. `dlna_manager_test.dart` 속성 테스트** (PBT-02 · 03 · 04 · 05)
  - [x] 9.1 P-DM-1 (시간 왕복), P-DM-2 (형식), P-DM-4 (소수 초 · 임의 문자열)
  - [x] 9.2 P-DM-3 (볼륨, 오라클), P-DM-5 (멱등성), P-DM-6 (탐색 뒤 선택의 불변 조건)
  - [x] 커밋: `test: DlnaManager 명령 전달 · 선택 정리 테스트 추가`

### `DlnaBackend` (FR-02)

- [x] **Step 10. `dlna_backend_test.dart` 재생 요청**: DB-01 ~ DB-15 (DB-07 은 Step 5 에서 작성)
- [x] **Step 11. `dlna_backend_test.dart` 폴링**: DB-16 ~ DB-31
- [x] **Step 12. `dlna_backend_test.dart` 갭리스 · 그 밖의 명령 · 주소 재발급**: DB-32 ~ DB-49
- [x] **Step 13. `dlna_backend_test.dart` 속성 테스트** (PBT-03 · 06)
  - [x] 13.1 P-DB-1 · P-DB-2 (폴링 순서, 모델 비교, 잠금 상태): 테스트 파일 안에 모델 작성, `forAll` 본문 안에서 `fakeAsync` (PT-5)
  - [x] 13.2 P-DB-3 (주소 비교), P-DB-4 (`allowedHost`), P-DB-5 (위치)
  - [x] 커밋: `test: DlnaBackend 재생 · 폴링 · 갭리스 테스트 추가`

### `WaveAudioHandler` (FR-04)

- [x] **Step 14. `test/features/player/wave_audio_handler_test.dart` 예시 기반 테스트** (새로 만듦)
  - [x] 14.1 명령 전달: WA-01 ~ WA-09
  - [x] 14.2 상태 알림: WA-10 ~ WA-23
- [x] **Step 15. `wave_audio_handler_test.dart` 속성 테스트** (PBT-03): P-WA-1, P-WA-2
  - [x] 커밋: `test: WaveAudioHandler 명령 전달 · 상태 알림 테스트 추가`

### 버그 · 문서 · 검증

- [x] **Step 16. 발견한 버그 처리** (FR-08, Functional Design 계획 Q1=A 기준, 패턴 RS-2)
  - [x] 16.1 Step 6 ~ 15 에서 규칙과 다르게 동작한 곳을 정리한다. 기준에 해당하는 것 (문서 · 주석의 의도와 다름, 예외 · 잘못된 상태) 만 버그로 본다
  - [x] 16.2 버그마다: 실패하는 테스트 → `lib/` 수정 → 별도 커밋 `fix: ...` → `docs/incidents/YYYY-MM-DD-<이름>.md` 작성
  - [x] 16.3 버그가 아닌 것은 지금 동작으로 테스트를 고정하고 `business-rules.md` 7절 관찰 사항에 추가
  - [x] 16.4 해당이 없으면 "없음" 으로 요약에 기록

- [x] **Step 17. 문서** (RESILIENCY-14 · 15, 패턴 RS-1 · RS-2)
  - [x] 17.1 `docs/failure-scenarios.md` 새로 만듦: 실기기 장애 상황 점검표 7개
  - [x] 17.2 `docs/incidents/README.md` 새로 만듦: 절차 5단계와 양식
  - [x] 17.3 `CLAUDE.md` 의 "Docs and references" 절에 위 두 문서를 가리키는 줄 추가 (기존 파일 수정)
  - [x] 커밋: `docs: 실기기 장애 상황 점검표와 문제 기록 절차 추가`

- [x] **Step 18. 검증** (unit 완료 기준, NFR-01 ~ NFR-05)
  - [x] 18.1 `dart format --output=none --set-exit-if-changed --line-length 120 lib test`
  - [x] 18.2 `flutter analyze --fatal-infos`
  - [x] 18.3 `flutter test` 전체: 통과 수 · 실패 수 기록, 기존 95개 포함 확인
  - [x] 18.4 커버리지: `flutter test --coverage` 결과를 저장소 밖 임시 폴더에 만들어 대상 4개 파일의 수치 계산 (각 80% 이상, NFR-01-D1 ~ D4). 미달이면 빠진 규칙의 테스트를 보강하고 다시 측정
  - [x] 18.5 새 테스트 파일 4개 10회 연속 실행 (NFR-03-D3)
  - [x] 18.6 `flutter test --test-randomize-ordering-seed=random` 3회 (NFR-03-D5)
  - [x] 18.7 전체 실행 시간 측정, 작업 전 (약 4초) 과 비교 (NFR-03-D4). 30초를 넘으면 PT-6 에 따라 조정
  - [x] 18.8 `tool/check.sh --skip-android` 통과 (NFR-02-D1)
  - [x] 18.9 `test/` 에 `config/tidal.json` 의 값이 없는지 검색 (SEC-D1), `git diff --stat main -- lib/` 로 운영 코드 변경 범위 확인 (NFR-05-D5)
  - [x] 18.10 복제 파일 (`*_new.*`, `*_modified.*`, `*_v2.*`) 이 없는지 확인

- [x] **Step 19. 요약 문서**
  - [x] 19.1 `aidlc-docs/construction/dart-playback-tests/code/code-summary.md` 새로 만듦: 수정 · 생성 파일 목록, 규칙 · 속성별 테스트 대응, 커버리지 수치, Step 18 의 실행 결과, 발견한 버그 · 관찰 사항, 계획에 없던 변경 · 계획에서 뺀 항목
  - [x] 커밋: `docs(aidlc): Code Generation (dart-playback-tests) 요약`

## 요구사항 · 규칙 추적

| 요구사항 | 규칙 · 속성 | Step |
| --- | --- | --- |
| FR-01 | PB-01 ~ PB-26, P-PB-1 ~ P-PB-5 | 6, 7 |
| FR-02 | DB-01 ~ DB-49, P-DB-1 ~ P-DB-5 | 5, 10, 11, 12, 13 |
| FR-03 | DM-01 ~ DM-29, P-DM-1 ~ P-DM-6 | 8, 9 |
| FR-04 | WA-01 ~ WA-23, P-WA-1 ~ P-WA-2 | 14, 15 |
| FR-07 (Dart) | `DlnaManager.forTesting(soapClient:)`, fake · 도우미 | 2, 3, 4 |
| FR-08 | 발견한 버그 | 16 |
| NFR-01 | 4개 파일 80% | 18.4 |
| NFR-02 | 점검 통과, 기존 테스트 유지 | 1.3, 2.2, 3.6, 18.1 ~ 18.3, 18.8 |
| NFR-03 | 결정성 · 속도 | 5, 18.5 ~ 18.7 |
| NFR-04 | 속성 18개, 모델, 생성기, seed | 4.3, 4.4, 7, 9, 13, 15 |
| NFR-05 | 도우미 위치, 기존 fake 유지, 이름 · 규칙 ID | 3, 4, 6 ~ 15 전반, 18.9 |
| SEC-D1 · D2 | 가짜 값 | 4.1, 18.9 |
| RESILIENCY-14 · 15 | 점검표, 절차 문서 | 17 |

규칙 127개와 속성 18개가 모두 어느 Step 에 들어 있다.

## 범위 요약

- 운영 코드 수정 1개 파일 (`dlna_manager.dart`), 설정 수정 1개 (`pubspec.yaml` + `pubspec.lock`)
- 테스트 도우미: 새 파일 7개, 수정 3개 (`fakes.dart`, `app_overrides.dart`, `player_manager_test.dart`)
- 테스트: 새 파일 4개 (규칙 127개의 예시 기반 테스트 + 속성 18개)
- 문서: 새 파일 2개 (`docs/`), 수정 1개 (`CLAUDE.md`), 요약 1개 (`aidlc-docs/`)
- 전체 Step 19개, 커밋 7개 이상 (버그 수정이 있으면 건마다 추가)
