# 논리 컴포넌트 (Logical Components) - dart-playback-tests

## 1. 인프라 구성 요소: 해당 없음

queue, cache, circuit breaker, 로드 밸런서 같은 인프라 구성 요소를 추가하지 않는다. 이 unit 은 운영 경로에 새 구성 요소를 넣지 않으며, 아래 구성 요소는 모두 테스트 지원 코드와 문서다.

## 2. 테스트 지원 구성 요소

Application Design (`components.md` 3절) 에서 정한 fake 에, 이 stage 의 패턴을 담는 파일 4개를 더한다.

### fake (외부 경계 대체)

| 파일 | 구성 요소 | 상태 | 책임 | 관련 패턴 |
| --- | --- | --- | --- | --- |
| `test/helpers/fake_native_channel.dart` | `FakeNativeChannel` | 새로 만듦 | MethodChannel 가로채기, 호출 기록, 메서드별 응답 · 실패, 응답 붙잡기, 네이티브 → Dart 호출 흉내 | DT-2, DT-5, VF-2 |
| `test/helpers/fake_soap_client.dart` | `FakeSoapClient` | 새로 만듦 | SOAP 액션 기록, 액션별 성공 여부, 전송 상태 · 위치 · 볼륨 응답 (고정값 또는 순서대로 줄 목록), 응답 붙잡기 | DT-5, VF-2 |
| `test/helpers/fake_backend.dart` | `FakeBackend` | `player_manager_test.dart` 에서 옮김, 호출 기록 추가 | `PlaybackBackend` 대체, 이벤트 주입 | AS-3, VF-2 |
| `test/helpers/fakes.dart` | `FakeAuthRepository` | 확장 | 사용자 토큰 결과 지정 | AS-3 |
| `test/helpers/app_overrides.dart` | `FakeApiClient`, `FakeSsdpDiscoveryService` | 확장 | 스트림 정보 결과 지정, 탐색 결과 지정 · 응답 붙잡기 | AS-3, DT-5 |

### 패턴을 담는 도우미 (이 stage 에서 추가)

| 파일 | 구성 요소 | 책임 | 관련 패턴 |
| --- | --- | --- | --- |
| `test/helpers/playback_fixtures.dart` | 곡 · 원격 기기 · 스트림 정보 생성 함수, 원격 스피커가 선택된 `DlnaManager` 생성 함수, `DlnaBackend` 테스트 묶음 | 기본 전제 조립, 가짜 값 규칙 | AS-1, AS-2, DT-3 |
| `test/helpers/event_descriptions.dart` | `describeEvent` (이벤트 → 한 줄 문자열) | 이벤트 순서 비교, 모델 출력과 같은 형식 | VF-1, PT-3 |
| `test/helpers/generators.dart` | `domain-entities.md` 3절의 생성기 | 속성 테스트 입력 | PT-1, PT-7 |
| `test/helpers/pbt_config.dart` | seed · 실행 횟수 설정 함수 | 고정 seed, `PBT_SEED` 환경 변수 | PT-2, PT-6 |

### 상태 기반 속성의 모델

| 모델 | 위치 | 본뜨는 것 |
| --- | --- | --- |
| pending seek 모델 | `test/features/player/phone_backend_test.dart` 안 | `business-logic-model.md` 1.3 |
| 폴링 모델 | `test/features/player/dlna_backend_test.dart` 안 | `business-logic-model.md` 3.2 |

모델은 그것을 쓰는 테스트 파일 안에 둔다. 한 파일에서만 쓰고, 속성과 나란히 있어야 읽기 쉽다. 운영 코드를 import 하지 않는다 (PT-3).

## 3. 구성 요소 관계

```text
테스트 파일 (phone_backend / dlna_backend / dlna_manager / wave_audio_handler)
  ├─ playback_fixtures.dart ──> fake_native_channel.dart
  │                         ├─> fake_soap_client.dart
  │                         ├─> fakes.dart (FakeAuthRepository)
  │                         ├─> app_overrides.dart (FakeApiClient, FakeSsdpDiscoveryService)
  │                         └─> fake_backend.dart
  ├─ event_descriptions.dart
  ├─ generators.dart ──> kiri_check
  └─ pbt_config.dart ──> kiri_check
```

- 테스트 파일은 `playback_fixtures.dart` 로 조립하고, 필요하면 fake 를 직접 만진다
- fake 끼리는 서로 의존하지 않는다
- `generators.dart` 는 fake 에 의존하지 않고 도메인 모델 (`MediaTrack`, `DlnaDevice`) 에만 의존한다
- 도우미 파일은 `lib/` 의 운영 코드와 `flutter_test`, `kiri_check`, `fake_async` 에만 의존한다

## 4. 문서 구성 요소 (복원력)

| 파일 | 내용 | 관련 패턴 |
| --- | --- | --- |
| `docs/failure-scenarios.md` (새로 만듦) | 실기기 장애 상황 점검표 7개, 언제 해 보는지, 결과를 어디에 적는지 | RS-1 |
| `docs/incidents/README.md` (새로 만듦) | 장애 대응 · 오류 교정 절차 5단계와 문제별 문서 양식 | RS-2 |
| `CLAUDE.md` 의 "Docs and references" 절 (수정) | 위 두 문서를 가리키는 줄 추가 | - |

## 5. Application Design 대비 달라진 점

| 항목 | Application Design | 이 stage |
| --- | --- | --- |
| fake 의 기능 | 호출 기록, 응답 지정 | "응답 붙잡기" 추가 (DT-5: 취소 지점 · 직렬화 · 늦은 응답 테스트에 필요) |
| `FakeSoapClient` 의 폴링 응답 | 고정값 필드 | 순서대로 줄 응답 목록도 지원 (PT-3: 폴링 순서 속성에 필요) |
| 도우미 파일 | fake 3개 파일 | 4개 추가 (`playback_fixtures`, `event_descriptions`, `generators`, `pbt_config`) |
| 문서 | 없음 | `docs/` 에 2개 추가, `CLAUDE.md` 1줄 |
| 운영 코드 | `DlnaManager.forTesting(soapClient:)` | 변경 없음 (같음) |

`unit-of-work.md` 의 포함 파일 목록에 위 추가분이 더해진다.
