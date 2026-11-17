# 논리 컴포넌트 (Logical Components) - android-native-tests

## 1. 인프라 구성 요소: 해당 없음

queue, cache, circuit breaker, 로드 밸런서 같은 인프라 구성 요소를 추가하지 않는다. 아래는 운영 코드의 새 구성 요소 (명령 분배의 분리) 와 테스트 지원 코드다.

## 2. 운영 코드 구성 요소

경로는 모두 `android/app/src/main/kotlin/com/example/tidal_connect_lite/` 아래다.

| 파일 | 구성 요소 | 상태 | 책임 | 관련 패턴 |
| --- | --- | --- | --- | --- |
| `PlaybackContracts.kt` | `CommandResult`, `PlayerControls`, `AuthControls`, `DeviceControls`, `ProxyRegistrar` | 새로 만듦 | router 의 결과 타입과 협력 인터페이스. 로직 없음 | TW-1, KR-1 |
| `PlaybackCommandRouter.kt` | `PlaybackCommandRouter` | 새로 만듦 | 채널 메서드 16개의 분배, 인자 해석, 반환 맵, 오류 변환 (CR 규칙) | TW-1, TW-6 |
| `ChannelAdapter.kt` | 채널 인자를 맵으로 바꾸는 함수, `CommandResult` 를 채널 응답으로 보내는 함수 | 새로 만듦 | Flutter 타입과 router 사이의 변환 (PC-01, PC-02) | KR-3 |
| `PlaybackCore.kt` | `PlaybackCore` | 수정 | `onMethodCall` 을 변환 → router → 변환으로 교체. 협력 인터페이스의 운영 구현 3개 (인증, 기기, 프록시 등록) 를 기존 private 함수에 연결. 그 밖은 그대로 | TW-7, KR-2 |
| `TidalPlayerManager.kt` | `TidalPlayerManager` | 수정 | `PlayerControls` 구현 선언과 `override` 추가. 메서드 본문은 그대로 | KR-1 |
| `TidalStreamProxyServer.kt` | `TidalStreamProxyServer` | 수정 | 생성자에 `port`, `httpClient` 추가. 주소의 포트를 실제로 열린 포트로 | KR-4 |

파일을 셋으로 나누는 이유: `PlaybackContracts.kt` 와 `PlaybackCommandRouter.kt` 는 Android · Flutter 타입을 import 하지 않는다. Flutter 타입에 닿는 변환은 `ChannelAdapter.kt` 에만 둔다.

설정: `android/app/build.gradle.kts` 에 `testOptions` 와 `testImplementation` 2개 (`tech-stack-decisions.md`).

## 3. 테스트 지원 구성 요소

경로는 모두 `android/app/src/test/kotlin/com/example/tidal_connect_lite/` 아래다.

### router 쪽 (TDD: RED 단계의 하위 에이전트가 작성)

| 파일 | 구성 요소 | 책임 | 관련 패턴 |
| --- | --- | --- | --- |
| `RouterFakes.kt` | `FakePlayerControls`, `FakeAuthControls`, `FakeDeviceControls`, `FakeProxyRegistrar` | 호출을 문자열로 기록, 반환값 · 예외 지정 | KV-2 |
| `RouterGenerators.kt` | 모르는 메서드 이름, 플레이어 동작 이름, 곡 ID, 재생 위치, 볼륨, 음질, 자격 증명, 등록 인자, 예외, 임의의 채널 호출 | router 속성의 입력 | KP-1 |
| `PlaybackCommandRouterTest.kt` | CR-01 ~ CR-13 의 예시 기반 테스트, P-CR-1 ~ P-CR-6 의 속성 테스트 | router 검증 | TW-2 ~ TW-4, KV-1, KV-4 |
| `ChannelAdapterTest.kt` | PC-01, PC-02 의 테스트 | 변환 검증. `MethodChannel.Result` 는 테스트 안에서 직접 구현해 받은 응답을 기록 | KR-3 |

### 프록시 쪽 (보호 테스트: RED 단계의 프록시 담당 하위 에이전트가 작성)

| 파일 | 구성 요소 | 책임 | 관련 패턴 |
| --- | --- | --- | --- |
| `FakeCdnServer.kt` | `FakeCdnServer` | `MockWebServer` 를 감싼다. 경로별 응답 · 응답 순서 지정, 받은 요청 (메서드 · 경로 · `Range`) 기록, 닫힌 포트의 주소 만들기 | KD-1, KD-4, KV-3 |
| `ProxyFixture.kt` | `ProxyFixture`, `ProxyResponse` | 프록시와 가짜 CDN 을 임시 포트로 띄우고 닫는다. 프록시에 GET · HEAD 를 보내 상태 · 헤더 · 본문을 돌려주는 함수 | KD-1 ~ KD-3, KV-3 |
| `ProxyGenerators.kt` | MIME 문자열, 등록 횟수, 허용 주소, Range 값, 바이트 내용, DASH 내용 | 프록시 속성의 입력 | KP-1 |
| `TidalStreamProxyServerTest.kt` | PX-01 ~ PX-38 의 예시 기반 테스트, P-PX-1 ~ P-PX-6 의 속성 테스트 | 프록시 검증 | TW-8, KP-3, KP-4 |

### 공용

| 파일 | 구성 요소 | 책임 | 관련 패턴 |
| --- | --- | --- | --- |
| `PbtSupport.kt` | seed · 실행 횟수로 `PropTestConfig` 를 만드는 함수, `runBlocking` 으로 감싸는 함수 | 고정 seed (20261117), `PBT_SEED` 환경 변수 | KP-1, KP-2 |

`PbtSupport.kt` 는 router 테스트와 프록시 테스트가 함께 쓴다. 뼈대 단계 (TW-1) 에서 이 세션이 먼저 만들어 두고, RED 의 하위 에이전트는 가져다 쓴다.

## 4. 구성 요소 관계

```text
운영 코드
  MethodChannel -> PlaybackCore.onMethodCall
                     -> ChannelAdapter (인자를 맵으로)
                     -> PlaybackCommandRouter.handle -> CommandResult
                          |- AuthControls     <- PlaybackCore 안의 구현 (TidalAuthManager, 플레이어 생성)
                          |- PlayerControls   <- TidalPlayerManager
                          |- DeviceControls   <- PlaybackCore 안의 구현 (볼륨, 권한, WifiLock)
                          `- ProxyRegistrar   <- PlaybackCore 안의 구현 (ensureProxyServer)
                     -> ChannelAdapter (결과를 채널 응답으로)

테스트
  PlaybackCommandRouterTest -> PlaybackCommandRouter + RouterFakes, RouterGenerators, PbtSupport
  ChannelAdapterTest        -> ChannelAdapter
  TidalStreamProxyServerTest -> ProxyFixture -> TidalStreamProxyServer + FakeCdnServer(MockWebServer)
                             -> ProxyGenerators, PbtSupport
```

- `PlaybackCommandRouter` 는 `PlaybackContracts.kt` 의 타입에만 의존한다
- router 쪽 테스트 파일과 프록시 쪽 테스트 파일은 `PbtSupport.kt` 말고는 서로 의존하지 않는다

## 5. Application Design 대비 달라진 점

| 항목 | Application Design | 이 stage |
| --- | --- | --- |
| 인터페이스의 위치 | `PlaybackCommandRouter.kt` 안 또는 `PlaybackContracts.kt` | `PlaybackContracts.kt` 로 확정 |
| 채널 응답 변환 | `PlaybackCore.onMethodCall` 안에서 직접 | `ChannelAdapter.kt` 의 함수 두 개로 분리 (JVM 테스트 가능함을 확인했기 때문) |
| 테스트 파일 | `PlaybackCommandRouterTest.kt`, `TidalStreamProxyServerTest.kt` | `ChannelAdapterTest.kt` 추가 |
| 테스트 도우미 | `FakeCdnServer`, fake 4개 | `ProxyFixture.kt`, 생성기 파일 2개, `PbtSupport.kt` 추가 |
| 작업 방식 | 정하지 않음 | router · 변환은 TDD 흐름 (뼈대 → RED → 고정 → GREEN → REFACTOR), 프록시는 보호 테스트 |

`unit-of-work.md` 의 포함 파일 목록에 위 추가분이 더해진다.
