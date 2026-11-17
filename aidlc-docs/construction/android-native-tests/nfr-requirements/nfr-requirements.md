# NFR 요구사항 (NFR Requirements) - android-native-tests

이 unit 은 Kotlin 테스트를 만들고 `PlaybackCore` 를 재구성한다. 아래 요구는 **테스트의 품질** 과 **재구성의 안전성** 에 대한 것이다. 앱의 실행 성능 · 가용성 요구는 이 unit 에 없다.

ID 는 `requirements.md` 의 NFR 번호를 잇는다 (`NFR-03-A1` = NFR-03 을 이 unit 에서 구체화한 첫 항목. unit 1 의 `-D` 와 구분해 `-A` 를 쓴다).

## 1. 배정된 NFR 의 구체화

### NFR-01 커버리지 (Kotlin 부분)

Kotlin 은 수치 목표가 없다 (`requirements.md` NFR-01). 대신 다음을 기준으로 한다.

| ID | 요구 | 측정 |
| --- | --- | --- |
| NFR-01-A1 | `business-rules.md` 의 CR 규칙 13개와 PX 규칙 38개 모두에 테스트가 하나 이상 있다 | 테스트 이름 맨 앞의 규칙 ID 표기 (`CR-01 ...`, 대괄호 없음) 를 규칙 목록과 대조 |
| NFR-01-A2 | PC 규칙 가운데 변환 부분 (PC-01, PC-02) 에 테스트가 있다. PC-03 은 CR-01 의 테스트와 `git diff` 로, 나머지 (PC-04 ~ PC-07) 는 NFR-06-A1 과 코드 검토로 확인한다 (2026-11-17 정정: 처음에 PC-01 ~ PC-03 으로 적었다) | 같은 방식 |
| NFR-01-A3 | 모든 테스트는 규칙 또는 속성을 하나 이상 검증한다 | 코드 검토 |

### NFR-02 점검 통과

| ID | 요구 | 측정 |
| --- | --- | --- |
| NFR-02-A1 | `(cd android && ./gradlew :app:testDebugUnitTest)` 통과 | 종료 코드 0, 테스트 결과 XML 의 실패 · 오류 0 |
| NFR-02-A2 | 기존 `DashManifestTest` 4개가 수정 없이 통과 | 같은 결과 |
| NFR-02-A3 | `tool/check.sh` 전체 (Kotlin 포함) 통과 | 종료 코드 0. 로컬에서는 `JAVA_HOME` 을 JDK 17 로 지정해 실행 |
| NFR-02-A4 | Dart 쪽 점검 (`tool/check.sh --skip-android`) 이 그대로 통과 (이 unit 은 Dart 코드를 바꾸지 않는다) | 종료 코드 0, 262개 통과 |

### NFR-03 결정성 · 속도

| ID | 요구 | 측정 |
| --- | --- | --- |
| NFR-03-A1 | 테스트는 외부 네트워크에 접근하지 않는다. 서버 (`TidalStreamProxyServer`, `FakeCdnServer`) 는 `127.0.0.1` 에만 바인딩한다 | 코드 검토: 테스트 안의 주소가 모두 루프백 |
| NFR-03-A2 | 고정 포트를 쓰지 않는다. 프록시와 가짜 CDN 모두 임시 포트 (0) 로 띄운다. 여러 테스트가 동시에 실행되거나 8765 포트가 쓰이고 있어도 실패하지 않는다 | 코드 검토, 8765 포트를 점유한 상태에서 실행 |
| NFR-03-A3 | 실제 시간을 기다리지 않는다 (`Thread.sleep` 없음). 연결 실패 경우 (PX-33) 는 닫힌 포트로 즉시 거부되게 만들고, 테스트용 HTTP 클라이언트의 타임아웃은 짧게 둔다 | 코드 검토, 실행 시간 |
| NFR-03-A4 | 새 Kotlin 테스트를 10회 연속 실행해 매번 같은 결과 | `./gradlew :app:testDebugUnitTest --rerun-tasks` 10회 |
| NFR-03-A5 | 새 Kotlin 테스트의 실행 시간 합계가 30초 이하 (Gradle 시작 · 컴파일 시간 제외) | 테스트 결과 XML 의 `time` 합계 |
| NFR-03-A6 | 테스트마다 서버를 새로 띄우고 끝나면 닫는다. 테스트끼리 등록부 · 응답 설정을 공유하지 않는다 | 코드 검토 |
| NFR-03-A7 | 테스트가 끝난 뒤 서버 스레드와 포트가 남지 않는다 | 10회 반복 실행 중 포트 고갈 · 멈춤이 없음 |

### NFR-04 속성 기반 테스트 (Kotlin)

| ID | 요구 | 근거 규칙 |
| --- | --- | --- |
| NFR-04-A1 | `business-logic-model.md` 3절의 속성 12개마다 PBT 가 하나 이상 있다 | PBT-01 |
| NFR-04-A2 | 왕복 속성 P-PX-6 (등록 → 조회로 내용 보존) 을 구현한다 | PBT-02 |
| NFR-04-A3 | 불변 조건 속성 (P-CR-1 ~ 5, P-PX-1, P-PX-4, P-PX-5) 을 구현한다 | PBT-03 |
| NFR-04-A4 | 결과의 결정성 속성 P-CR-6 을 구현한다 | PBT-04 |
| NFR-04-A5 | 오라클 속성 P-PX-2 는 테스트 안의 참조 표와 비교한다 | PBT-05 |
| NFR-04-A6 | 상태 기반 속성 P-PX-3 은 "최근 3개" 모델을 두고 등록 하나마다 실제 응답과 모델을 비교한다. 등록 0회도 포함한다 | PBT-06 |
| NFR-04-A7 | 생성기는 `domain-entities.md` 4절의 범위를 따르고 한 파일에 모은다 | PBT-07 |
| NFR-04-A8 | 프레임워크의 축소 기능을 끄지 않는다 | PBT-08 |
| NFR-04-A9 | seed 는 unit 1 과 같은 고정값 (20261117) 을 쓰고 환경 변수 `PBT_SEED` 로 바꿀 수 있다. 실패 출력에 seed 와 축소된 입력이 나온다 | PBT-08 |
| NFR-04-A10 | PBT 는 일반 `testDebugUnitTest` 에 포함되어 `tool/check.sh` 와 CI 에서 함께 실행된다 | PBT-08 |
| NFR-04-A11 | 규칙마다 예시 기반 테스트가 있고 PBT 는 그 위에 더한다 | PBT-10 |
| NFR-04-A12 | 속성당 실행 횟수를 명시한다. 프레임워크 기본값 (1000회) 을 그대로 쓰지 않는다. 소켓을 쓰지 않는 router 속성은 100회, 실제 HTTP 를 쓰는 프록시 속성은 NFR-03-A5 를 지키는 범위에서 정한다 | NFR-03-A5 |

### NFR-05 유지보수성

`unit-of-work-story-map.md` 는 NFR-05 를 unit 1 에만 배정했지만, 같은 원칙을 Kotlin 에 맞춰 적용한다.

| ID | 요구 | 측정 |
| --- | --- | --- |
| NFR-05-A1 | fake · 생성기 · 서버 도우미는 테스트와 같은 패키지 (`android/app/src/test/kotlin/com/example/tidal_connect_lite/`) 에 둔다 (Application Design 계획 Q6=A) | 파일 위치 |
| NFR-05-A2 | 테스트 이름은 규칙 ID 를 맨 앞에 적고 한국어 문장으로 쓴다 (Kotlin 의 역따옴표 함수 이름). JVM 메서드 이름에는 대괄호를 쓸 수 없어 unit 1 과 달리 대괄호 없이 적는다 (2026-11-17 정정). 기존 `DashManifestTest` 의 영어 이름은 그대로 둔다 | 코드 검토 |
| NFR-05-A3 | 새 운영 코드 (`PlaybackCommandRouter`, 인터페이스) 는 기존 Kotlin 코드처럼 한국어 KDoc 주석을 단다 | 코드 검토 |

## 2. 재구성 안전성 (이 unit 고유)

| ID | 요구 | 측정 |
| --- | --- | --- |
| NFR-06-A1 | 재구성 뒤 앱이 빌드된다 | `flutter build apk --debug --dart-define-from-file=config/tidal.json` 성공 |
| NFR-06-A2 | 채널 계약이 재구성 전과 같다: 채널 이름 2개, 메서드 이름 16개, 인자 키, 반환 맵의 키와 값 | CR-01 의 테스트가 메서드 표 전체를 검증. 채널 이름 상수는 `git diff` 로 변경 없음을 확인 |
| NFR-06-A3 | `PlaybackCore` 에 남는 부분 (`attach`, 이벤트 전송, 볼륨 관찰, Dart 로 되묻는 요청, 프록시 수명 관리) 의 코드는 옮기지 않고 그대로 둔다 | `git diff` 검토: 해당 함수 본문에 변경 없음 |
| NFR-06-A4 | `TidalStreamProxyServer` 의 새 생성자 매개변수는 기본값이 지금 동작이다. `PlaybackCore.ensureProxyServer` 의 호출 코드는 바꾸지 않는다 | `git diff` 검토 |
| NFR-06-A5 | 운영 빌드에 테스트 전용 의존성이 들어가지 않는다 | 새 의존성이 모두 `testImplementation` |
| NFR-06-A6 | 재구성의 동작 동일성은 자동 테스트와 빌드로만 확인된다. 실기기 확인은 범위 밖이므로 (NFR-02), 확인하지 못한 부분을 Code Generation 요약에 적는다 | 요약 문서 |

## 3. 범주별 평가

| 범주 | 평가 |
| --- | --- |
| 확장성 | 해당 없음 |
| 성능 | 앱 성능 요구 없음. router 는 지금의 `when` 분기를 옮긴 것이라 호출 경로에 단계가 하나 늘 뿐이다. 테스트 실행 시간만 해당 (NFR-03-A5) |
| 가용성 | 해당 없음. 운영되는 서비스가 없다 |
| 보안 | 보안 확장은 쓰지 않는다. 테스트 서버는 루프백에만 바인딩한다 (NFR-03-A1). 테스트 데이터에 실제 토큰 · 키 · 서명 주소를 넣지 않는다 (unit 1 의 SEC-D1 · D2 와 같음) |
| 신뢰성 | 테스트의 결정성 (NFR-03), 속성 테스트의 재현성 (NFR-04-A8 ~ A10), 재구성 안전성 (NFR-06) |
| 유지보수성 | NFR-05 |
| 사용성 | 해당 없음 |

## 4. 확장 규칙에서 나오는 요구

### Property-Based Testing

| 규칙 | 이 stage 의 요구 | 상태 |
| --- | --- | --- |
| PBT-09 | Kotlin 용 프레임워크를 선택하고 문서화, 의존성에 포함 | `tech-stack-decisions.md` D1. Gradle 반영은 Code Generation |
| PBT-08 | seed 정책 | unit 1 과 같은 고정 seed (NFR-04-A9) |

Dart (unit 1) 와 Kotlin 양쪽에 프레임워크가 정해져, "PBT 적용 대상 코드가 있는 언어마다 프레임워크 선택" (PBT-09) 이 충족된다.

### Resiliency

운영 경로에 새 외부 호출 · 저장소 · 배포 구성을 추가하지 않는다. 새로 생기는 요구는 없다.

이 unit 의 테스트가 기존 복원력 동작을 고정한다: 서명 주소 만료 시 재발급 1회 (PX-26 ~ PX-31), CDN 실패 · 연결 실패 시의 오류 응답 (PX-32, PX-33), 허용되지 않은 주소 거부 (PX-11), 플레이어가 없을 때의 오류 응답 (CR-05). 프록시의 CDN 타임아웃 (연결 20초, 읽기 120초, 쓰기 20초) 은 기본값으로 유지한다 (NFR-06-A4).

## 5. 배정 NFR 대조 (NR-1)

| `unit-of-work-story-map.md` 에서 이 unit 에 배정된 NFR | 이 문서 |
| --- | --- |
| NFR-01 (Kotlin: 동작 목록 충족) | NFR-01-A1 ~ A3 |
| NFR-02 | NFR-02-A1 ~ A4 |
| NFR-03 | NFR-03-A1 ~ A7 |
| NFR-04 (Kotlin) | NFR-04-A1 ~ A12 |
| (배정 밖, 원칙 적용) NFR-05 | NFR-05-A1 ~ A3 |
| (이 unit 고유) 재구성 안전성 | NFR-06-A1 ~ A6 |
