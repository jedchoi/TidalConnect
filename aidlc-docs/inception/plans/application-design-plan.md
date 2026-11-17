# Application Design 계획 (Application Design Plan)

**범위**: 새 기능 컴포넌트는 없다. 이 설계는 FR-07 의 "테스트 대체 지점" 을 6개 컴포넌트가 같은 방식으로 쓰도록 정한다 (Minimal 깊이). 상세 테스트 케이스와 속성 (PBT-01) 은 unit 별 Functional Design 에서 다룬다.

## 코드에서 확인한 현재 상태

| 컴포넌트 | 테스트를 막는 것 | 이미 있는 대체 지점 |
| --- | --- | --- |
| `PhoneBackend` | `TidalSdkNativeBridge` 정적 호출 (MethodChannel) | 생성자 `nativeEvents` 스트림 주입 |
| `DlnaBackend` | `TidalSdkNativeBridge` 정적 호출 (`stopTrack`, `registerTrackStream`, `setStreamingLock`, `setStreamRefresher`), `Timer.periodic` 1초 폴링 | 생성자로 `auth`, `api`, `dlna` 주입 |
| `DlnaManager` | `_soapClient = UPnPSoapClient()` 고정 생성, `SharedPreferences` | `DlnaManager.forTesting(ssdpService:)`, `UPnPSoapClient({Dio? dio})`, `SharedPreferences.setMockInitialValues` |
| `WaveAudioHandler` | 없음 | 생성자로 `PlayerManager`, `dlnaManager` 주입, `PlayerManager.forTesting()` + `configure(phone:, dlna:)` |
| `TidalStreamProxyServer` | 포트 8765 고정, `OkHttpClient` 내부 생성, `android.util.Log` | `streamRefresher` 함수 주입 |
| `PlaybackCore` | `object` 싱글톤, `Context` · `FlutterEngine` · `AudioManager` · `WifiManager` · TIDAL SDK 에 직접 의존 | 없음 |

## 실행 단계

- [x] 1. 요구사항 (`requirements.md`) 과 Reverse Engineering 산출물, 대상 코드 6개 파일과 `test/helpers/` 읽기
- [x] 2. 현재 대체 지점 조사 (위 표)
- [x] 3. 아래 질문에 대한 답변 수집 · 모호성 분석
- [x] 4. `aidlc-docs/inception/application-design/components.md` 생성 - 대상 컴포넌트, 새 테스트 지원 컴포넌트 (fake · 대체 지점) 의 이름 · 목적 · 책임 · 인터페이스
- [x] 5. `aidlc-docs/inception/application-design/component-methods.md` 생성 - 바뀌는 생성자 · 새 인터페이스 · fake 의 메서드 시그니처 (비즈니스 규칙은 Functional Design)
- [x] 6. `aidlc-docs/inception/application-design/services.md` 생성 - 테스트에서의 조립 방식 (어떤 fake 를 어떻게 엮는지), 운영 조립 (`main.dart`, `providers.dart`, `PlaybackCore.attach`) 이 그대로임을 확인
- [x] 7. `aidlc-docs/inception/application-design/component-dependency.md` 생성 - 의존성 매트릭스, 통신 방식, 데이터 흐름 도식
- [x] 8. `aidlc-docs/inception/application-design/application-design.md` 생성 - 위 문서 통합
- [x] 9. 설계 완전성 · 일관성 검증 (FR-01 ~ FR-09 가 모두 컴포넌트에 배정되었는지, 순환 의존이 없는지, 메서드가 책임과 맞는지)

## 질문

각 질문의 `[Answer]:` 뒤에 선택지 문자를 적어 주세요. 선택지마다 운영 코드가 얼마나 바뀌는지 적었습니다.

## Question 1
Dart 에서 `TidalSdkNativeBridge` (정적 메서드, 플랫폼 채널) 를 테스트에서 어떻게 대체할까요? `PhoneBackend` 와 `DlnaBackend` 테스트 모두에 적용됩니다.

A) 채널 수준에서 가로채기 - `TidalSdkNativeBridge` 는 그대로 두고, 테스트가 Flutter 테스트 바인딩의 `setMockMethodCallHandler` 로 MethodChannel 호출을 가로챈다. 운영 코드 변경 0. 채널 메서드 이름 · 인자 (`playTrack`, `{trackId: ...}`) 까지 실제로 검증된다 (권장)

B) 인터페이스 추출 - `NativeBridge` 추상 클래스를 만들고 `PhoneBackend` · `DlnaBackend` · `PlayerManager` 가 인스턴스를 주입받게 바꾼다. 테스트는 가짜 구현을 넣는다. 운영 코드 변경 큼 (호출부 약 20곳), 채널 문자열은 별도 테스트가 필요

X) Other (please describe after [Answer]: tag below)

[Answer]: A (사용자 지시 "추천으로 진행해줘" 에 따라 권장안 기입)

## Question 2
`DlnaBackend` 와 `WaveAudioHandler` 테스트에서 `DlnaManager` 를 무엇으로 넣을까요?

A) 실제 `DlnaManager` + 가짜 SOAP 클라이언트 - `DlnaManager.forTesting` 에 `soapClient` 매개변수를 추가하고, 테스트는 SOAP 응답만 가짜로 준다. fake 가 하나로 줄고 `DlnaManager` 의 시간 문자열 변환 · 기기 판정 로직이 백엔드 테스트에서도 함께 검증된다. 운영 코드 변경: 생성자 매개변수 1개 (권장)

B) 가짜 `DlnaManager` - `DlnaManager` 를 상속한 `FakeDlnaManager` 가 메서드를 덮어써 정해진 값을 돌려준다. 백엔드 테스트가 `DlnaManager` 구현과 분리된다. `DlnaManager` 자체 테스트에는 어차피 A 의 `soapClient` 주입이 필요하다

X) Other (please describe after [Answer]: tag below)

[Answer]: A (사용자 지시 "추천으로 진행해줘" 에 따라 권장안 기입)

## Question 3
`DlnaBackend` 의 1초 주기 폴링 (`Timer.periodic`) 을 테스트에서 어떻게 제어할까요?

A) `fake_async` 로 가짜 시간 진행 - 운영 코드는 그대로 두고 테스트가 `fakeAsync` 안에서 `elapse(1초)` 로 타이머를 돌린다. `fake_async` 는 이미 `pubspec.lock` 에 있다 (flutter_test 의존). 운영 코드 변경 0 (권장)

B) 폴링 간격 · 타이머 주입 - `DlnaBackend` 생성자에 `pollInterval` 또는 타이머 팩토리를 추가한다. 운영 코드 변경: 생성자 매개변수 1 ~ 2개

X) Other (please describe after [Answer]: tag below)

[Answer]: A (사용자 지시 "추천으로 진행해줘" 에 따라 권장안 기입)

## Question 4
Kotlin `PlaybackCore` 는 `object` 이고 Android 클래스 (`Context`, `AudioManager`, `WifiManager`, `FlutterEngine`) 와 TIDAL SDK 에 직접 의존해서, 지금 구조로는 JVM 단위 테스트 (`./gradlew :app:testDebugUnitTest`) 에서 실행할 수 없습니다. 어떻게 테스트할까요?

A) 명령 분배 로직 분리 - `onMethodCall` 의 메서드 분배 · 인자 해석 · 반환 맵 · 오류 변환을 새 일반 클래스 (예: `PlaybackCommandRouter`) 로 옮기고, 플레이어 · 인증 · 프록시 · 볼륨은 작은 인터페이스로 받는다. `PlaybackCore` 는 `object` 로 남아 실제 구현을 엮어 router 에 넘긴다. 테스트는 router 를 가짜 구현으로 검증한다. 새 테스트 의존성 없음. 운영 코드 변경 중간 (`PlaybackCore.kt` 재구성, 채널 계약은 그대로). `attach` · 볼륨 관찰 · WifiLock 같은 Android 연결부는 테스트 대상에서 빠진다 (권장)

B) Robolectric 도입 - `PlaybackCore` 를 거의 그대로 두고 Robolectric 으로 Android 클래스를 흉내 내 테스트한다. 운영 코드 변경 작음. 새 테스트 의존성 (Robolectric) 추가, 테스트 실행이 느려지고, TIDAL SDK 플레이어 생성은 여전히 대체 지점이 필요

C) A + B - 분배 로직은 A 로, Android 연결부 (`attach`, 볼륨, WifiLock) 는 Robolectric 으로

X) Other (please describe after [Answer]: tag below)

[Answer]: A (사용자 지시 "추천으로 진행해줘" 에 따라 권장안 기입)

## Question 5
Kotlin `TidalStreamProxyServer` 테스트는 어느 수준에서 할까요? (NFR-03 은 루프백 주소 + 임시 포트만 쓰도록 정했습니다)

A) 실제 HTTP 왕복 - 테스트가 서버를 `127.0.0.1` 의 임시 포트에 띄우고 실제 HTTP 요청 (GET · HEAD · Range) 을 보낸다. 업스트림 CDN 은 가짜 로컬 서버로 대체한다. 상태 코드 · 헤더 · 본문이 실제 렌더러가 받는 그대로 검증된다. 운영 코드 변경: 생성자에 `port` (기본 8765) 와 `httpClient` (기본 기존 설정) 매개변수 추가 (권장)

B) `serve()` 직접 호출 - 소켓을 열지 않고 가짜 `IHTTPSession` 으로 `serve()` 를 불러 `Response` 객체를 검사한다. 더 빠르지만 NanoHTTPD 가 실제로 내보내는 헤더 · 본문 스트리밍은 검증하지 않는다. 운영 코드 변경: `httpClient` 매개변수 추가

X) Other (please describe after [Answer]: tag below)

[Answer]: A (사용자 지시 "추천으로 진행해줘" 에 따라 권장안 기입)

## Question 6
이번에 추가하는 fake · 테스트 도우미를 어디에 둘까요?

A) Dart 는 기존 `test/helpers/` 에 추가 (CLAUDE.md 방식), Kotlin 은 `android/app/src/test/kotlin/.../` 에 테스트와 같은 패키지로 둔다 (권장)

B) Dart 는 테스트 파일마다 그 안에 둔다 (기존 `player_manager_test.dart` 의 `FakeBackend` 방식), 여러 테스트가 쓰는 것만 `test/helpers/`

X) Other (please describe after [Answer]: tag below)

[Answer]: A (사용자 지시 "추천으로 진행해줘" 에 따라 권장안 기입)
