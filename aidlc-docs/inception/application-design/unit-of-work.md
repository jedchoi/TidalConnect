# Unit of Work

분해 기준: 언어 · 도구 (계획 Q1=A). 진행 순서: Dart → Kotlin → CI (Q2=A). 이 앱은 하나의 모놀리스이고, 아래 unit 은 배포 단위가 아니라 개발 · 검토 단위다.

| 순서 | unit | 목적 | FR |
| --- | --- | --- | --- |
| 1 | `dart-playback-tests` | Dart 재생 · DLNA 컴포넌트 4개의 테스트와 그에 필요한 대체 지점 | FR-01, FR-02, FR-03, FR-04 |
| 2 | `android-native-tests` | Kotlin 명령 분배 분리, 프록시 서버 테스트 | FR-05, FR-06 |
| 3 | `ci-quality-gate` | 커버리지 검사와 APK 산출물 업로드 | FR-09 |

FR-07 (대체 지점) 과 FR-08 (발견 버그 수정) 은 unit 1 · 2 가 각자 자기 범위 안에서 맡는다 (Q4=A).

---

## Unit 1: `dart-playback-tests`

### 목적
`PhoneBackend`, `DlnaBackend`, `DlnaManager`, `WaveAudioHandler` 의 공개 동작 · 이벤트 변환 · 오류 경로를 자동 테스트로 덮고, 각 파일의 라인 커버리지를 80% 이상으로 올린다.

### 책임
- Dart 대체 지점 추가: `DlnaManager.forTesting(soapClient:)`
- 테스트 지원 컴포넌트: `FakeNativeChannel`, `FakeSoapClient` 새로 만들기, `FakeSsdpDiscoveryService` · `FakeAuthRepository` · `FakeApiClient` · `FakeBackend` 확장
- 테스트 4개 파일 작성 (예시 기반 + PBT)
- 이 범위에서 발견한 버그 수정 (FR-08)
- 프로젝트 전체에 한 번만 정하면 되는 복원력 결정: RESILIENCY-14 질문 (복원력 테스트 방식) 과 RESILIENCY-15 의 가벼운 장애 대응 · COE 제안을 이 unit 의 NFR Design 에서 다룬다 (첫 unit 이므로)

### 포함 파일

| 구분 | 파일 |
| --- | --- |
| 운영 코드 (수정) | `lib/features/dlna/data/dlna_manager.dart` |
| 테스트 도우미 (새로 만듦) | `test/helpers/fake_native_channel.dart`, `test/helpers/fake_soap_client.dart`, `test/helpers/fake_backend.dart` |
| 테스트 도우미 (수정) | `test/helpers/fakes.dart`, `test/helpers/app_overrides.dart`, `test/features/player/player_manager_test.dart` (`FakeBackend` 를 도우미로 옮김) |
| 테스트 (새로 만듦) | `test/features/player/phone_backend_test.dart`, `test/features/player/dlna_backend_test.dart`, `test/features/player/wave_audio_handler_test.dart`, `test/features/dlna/dlna_manager_test.dart` |
| 설정 (수정 가능) | `pubspec.yaml` (`dev_dependencies`: PBT 프레임워크, 필요하면 `fake_async`) |
| NFR Design 에서 추가 (2026-11-17) | 테스트 도우미 `test/helpers/playback_fixtures.dart`, `event_descriptions.dart`, `generators.dart`, `pbt_config.dart` / 문서 `docs/failure-scenarios.md`, `docs/incidents/README.md`, `CLAUDE.md` 1줄 |

### 배정된 요구사항
FR-01, FR-02, FR-03, FR-04, FR-07 (Dart 부분), FR-08 (이 범위에서 발견한 것), NFR-01 (달성), NFR-02, NFR-03, NFR-04 (Dart), NFR-05

### 실행할 CONSTRUCTION stage

| Stage | 실행 | 근거 |
| --- | --- | --- |
| Functional Design | EXECUTE | 컴포넌트별 테스트 대상 동작과 속성 식별 (PBT-01), `application-design.md` 7절 관찰 사항 4번 (FR-01 예외 범위) 확정 |
| NFR Requirements | EXECUTE | Dart PBT 프레임워크 선택 (PBT-09), `fake_async` 의존성 선언 방식 |
| NFR Design | EXECUTE | 결정적 테스트 패턴, RESILIENCY-14 · 15 |
| Infrastructure Design | SKIP | 인프라 없음 |
| Code Generation | EXECUTE | 항상 |

### 완료 기준
- Dart 대상 4개 파일 각각 라인 커버리지 80% 이상 (`flutter test --coverage`)
- `tool/check.sh --skip-android` 통과, 기존 95개 테스트 그대로 통과
- 새 테스트 10회 연속 실행 결과 동일, 추가 실행 시간 30초 이하
- 식별한 속성마다 PBT 가 있음

---

## Unit 2: `android-native-tests`

### 목적
`PlaybackCore` 의 명령 분배를 테스트 가능한 `PlaybackCommandRouter` 로 분리해 검증하고, `TidalStreamProxyServer` 의 HTTP 동작 (상태 코드, 접근 제어, HEAD, Range, 주소 갱신) 을 루프백 테스트로 검증한다.

### 책임
- Kotlin 대체 지점 추가: `PlaybackCommandRouter` 와 협력 인터페이스 (`PlayerControls`, `AuthControls`, `DeviceControls`, `ProxyRegistrar`, `CommandResult`), `TidalStreamProxyServer` 생성자의 `port` · `httpClient`
- `PlaybackCore.onMethodCall` 을 router 위임으로 바꾸기 (채널 계약 불변), `TidalPlayerManager` 에 `PlayerControls` 구현 선언
- 테스트 지원 컴포넌트: `FakeCdnServer`, router 용 fake 4개
- 테스트 2개 파일 작성 (예시 기반 + PBT)
- 이 범위에서 발견한 버그 수정 (FR-08). `application-design.md` 7절 관찰 사항 1 ~ 3번이 여기에 속한다

### 포함 파일

| 구분 | 파일 |
| --- | --- |
| 운영 코드 (새로 만듦) | `android/app/src/main/kotlin/com/example/tidal_connect_lite/PlaybackCommandRouter.kt` (인터페이스 포함 또는 별도 파일) |
| 운영 코드 (수정) | `PlaybackCore.kt`, `TidalPlayerManager.kt`, `TidalStreamProxyServer.kt` (같은 폴더) |
| 테스트 (새로 만듦) | `android/app/src/test/kotlin/com/example/tidal_connect_lite/PlaybackCommandRouterTest.kt`, `TidalStreamProxyServerTest.kt`, fake 파일들 (같은 폴더) |
| 설정 (수정) | `android/app/build.gradle.kts` (테스트 의존성, 단위 테스트 설정) |
| NFR Design 에서 추가 (2026-11-17) | 운영 코드 `PlaybackContracts.kt` (인터페이스 · 결과 타입), `ChannelAdapter.kt` (채널 응답 변환) / 테스트 `ChannelAdapterTest.kt`, `RouterFakes.kt`, `RouterGenerators.kt`, `FakeCdnServer.kt`, `ProxyFixture.kt`, `ProxyGenerators.kt`, `PbtSupport.kt` |

### 배정된 요구사항
FR-05, FR-06, FR-07 (Kotlin 부분), FR-08 (이 범위에서 발견한 것), NFR-01 (Kotlin 부분: 수치 없이 FR-05 · FR-06 동작 목록 충족), NFR-02, NFR-03, NFR-04 (Kotlin)

### 실행할 CONSTRUCTION stage

| Stage | 실행 | 근거 |
| --- | --- | --- |
| Functional Design | EXECUTE | 채널 메서드 16개의 인자 · 반환 · 오류 규칙, 프록시 응답 규칙, 속성 식별 (PBT-01), FR-05 의 400 항목 정정 |
| NFR Requirements | EXECUTE | Kotlin PBT 프레임워크 선택 (PBT-09), `FakeCdnServer` 구현 수단, `android.util.Log` 처리 방식 |
| NFR Design | EXECUTE | 임시 포트 · 서버 수명 관리 패턴, 결정적 테스트 패턴 |
| Infrastructure Design | SKIP | 인프라 없음 |
| Code Generation | EXECUTE | 항상 |

### 완료 기준
- FR-05 · FR-06 에 적힌 동작과 오류 경로가 모두 테스트됨 (Functional Design 에서 정정한 목록 기준)
- `(cd android && ./gradlew :app:testDebugUnitTest)` 통과, 기존 `DashManifestTest` 그대로 통과
- `flutter build apk --debug` 가 성공해 `PlaybackCore` 재구성 뒤에도 앱이 빌드됨
- 새 테스트 10회 연속 실행 결과 동일
- 식별한 속성마다 PBT 가 있음

---

## Unit 3: `ci-quality-gate`

### 목적
NFR-01 의 커버리지 기준을 로컬 점검과 CI 가 자동으로 검사하게 하고, CI 가 debug APK 를 산출물로 올리게 한다.

### 책임
- `CoverageGate` 작성: lcov 결과에서 대상 4개 파일의 커버리지를 계산해 80% 미만 (또는 파일이 lcov 에 없음) 이면 실패
- `tool/check.sh`: Dart 테스트를 커버리지 수집으로 바꾸고 `CoverageGate` 호출
- `.github/workflows/check.yml`: debug APK 빌드, workflow 산출물 업로드
- 명령이 바뀌면 `CLAUDE.md` 의 Commands 절과 `README.md` 의 해당 부분 갱신

### 포함 파일

| 구분 | 파일 |
| --- | --- |
| 새로 만듦 | `tool/` 아래 `CoverageGate` 스크립트 (이름 · 언어는 이 unit 의 NFR Requirements 에서 확정) |
| 수정 | `tool/check.sh`, `.github/workflows/check.yml`, `.gitignore` (`coverage/` 제외가 없으면 추가), 문서 (`CLAUDE.md`, `README.md`) |

### 배정된 요구사항
FR-09, NFR-01 (검사 자동화), NFR-02

### 실행할 CONSTRUCTION stage

| Stage | 실행 | 근거 |
| --- | --- | --- |
| Functional Design | SKIP | 비즈니스 로직 없는 설정 · 스크립트 (계획 Q3=A) |
| NFR Requirements | EXECUTE | 검사 스크립트의 언어 · 도구 결정. 스크립트를 PBT 프레임워크가 있는 언어로 쓰면 lcov 해석 로직의 PBT 적용 여부도 여기서 판단 |
| NFR Design | SKIP | 계획 Q3=A |
| Infrastructure Design | SKIP | 인프라 없음 |
| Code Generation | EXECUTE | 항상 |

### 완료 기준
- `tool/check.sh` 가 커버리지 미달 시 실패하고, 기준 충족 시 통과함 (미달 상황을 만들어 확인)
- `tool/check.sh` 전체 통과
- `check.yml` 문법이 유효하고 APK 빌드 · 업로드 단계가 있음 (실제 CI 실행 확인은 푸시가 필요하므로 사용자 확인 사항으로 남김)
