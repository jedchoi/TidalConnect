# NFR 요구사항 (NFR Requirements) - dart-playback-tests

이 unit 은 테스트 코드와 작은 대체 지점을 만든다. 아래 요구는 **테스트의 품질** 에 대한 것이다. 앱의 실행 성능 · 가용성 요구는 이 unit 에 없다.

ID 는 `requirements.md` 의 NFR 번호를 잇는다 (`NFR-01-D1` = NFR-01 을 이 unit 에서 구체화한 첫 항목).

## 1. 배정된 NFR 의 구체화

### NFR-01 커버리지

| ID | 요구 | 측정 |
| --- | --- | --- |
| NFR-01-D1 | `lib/features/player/data/backends/phone_backend.dart` 라인 커버리지 80% 이상 (현재 0%) | `flutter test --coverage` 가 만든 `coverage/lcov.info` 에서 파일별 `LH / LF` |
| NFR-01-D2 | `lib/features/player/data/backends/dlna_backend.dart` 80% 이상 (현재 0%) | 같음 |
| NFR-01-D3 | `lib/features/dlna/data/dlna_manager.dart` 80% 이상 (현재 15.4%) | 같음 |
| NFR-01-D4 | `lib/features/player/data/wave_audio_handler.dart` 80% 이상 (현재 lcov 에 없음) | 같음. lcov 에 파일이 나타나야 함 |

수치를 맞추려고 의미 없는 테스트를 넣지 않는다. 모든 테스트는 `business-rules.md` 의 규칙 또는 `business-logic-model.md` 의 속성을 하나 이상 검증한다.

### NFR-02 점검 통과

| ID | 요구 | 측정 |
| --- | --- | --- |
| NFR-02-D1 | `tool/check.sh --skip-android` 통과 (포맷 줄 길이 120, `flutter analyze --fatal-infos`, `flutter test`) | 명령의 종료 코드 0 |
| NFR-02-D2 | 기존 95개 테스트가 수정 없이 통과. 예외: `player_manager_test.dart` 는 `FakeBackend` 를 `test/helpers/` 로 옮기는 import 변경만 허용 | `flutter test` 결과 |
| NFR-02-D3 | 새 의존성 추가 뒤에도 `flutter analyze --fatal-infos` 가 info 0건 | 명령 출력 |

### NFR-03 결정성 · 속도

| ID | 요구 | 측정 |
| --- | --- | --- |
| NFR-03-D1 | 새 테스트는 실제 네트워크 소켓, 실제 플랫폼 채널, 실제 TIDAL 계정에 접근하지 않는다 | 코드 검토: 테스트가 쓰는 외부 경계가 모두 fake (`FakeNativeChannel`, `FakeSoapClient`, `FakeSsdpDiscoveryService`, `FakeAuthRepository`, `FakeApiClient`) |
| NFR-03-D2 | 실제 시간을 기다리지 않는다. 1초 폴링은 `fake_async` 로 진행하고, `Future.delayed` · `sleep` 으로 실제 대기하는 테스트가 없다 | 코드 검토, 실행 시간 |
| NFR-03-D3 | 새 테스트 파일 4개를 10회 연속 실행해 매번 같은 결과 (통과 수 동일, 실패 0) | 같은 명령을 10회 반복 |
| NFR-03-D4 | `flutter test` 전체 실행 시간 증가가 30초 이하 (현재 약 4초) | 작업 전후 `time flutter test` 비교 |
| NFR-03-D5 | 테스트끼리 상태를 공유하지 않는다. 실행 순서를 바꿔도 결과가 같다 | `flutter test --test-randomize-ordering-seed=random` 으로 3회 실행 |

### NFR-04 속성 기반 테스트

| ID | 요구 | 근거 규칙 |
| --- | --- | --- |
| NFR-04-D1 | `business-logic-model.md` 5절의 속성 18개마다 PBT 가 하나 이상 있다 | PBT-01 |
| NFR-04-D2 | 왕복 속성 P-DM-1 을 구현한다 | PBT-02 |
| NFR-04-D3 | 불변 조건 속성 (P-PB-1, 3, 4 / P-DM-2, 4, 6 / P-DB-2 ~ 5 / P-WA-1, 2) 을 구현한다 | PBT-03 |
| NFR-04-D4 | 멱등성 속성 P-DM-5 를 구현한다 | PBT-04 |
| NFR-04-D5 | 오라클 속성 P-PB-2, P-DM-3 을 구현한다 | PBT-05 |
| NFR-04-D6 | 상태 기반 속성 P-PB-5, P-DB-1 은 단순화한 모델을 두고, 명령 (응답) 하나마다 실제 결과와 모델 결과를 비교한다. 길이 0 인 순서도 포함한다 | PBT-06 |
| NFR-04-D7 | 생성기는 `domain-entities.md` 3절의 범위를 따르고, 여러 테스트가 쓰는 생성기는 `test/helpers/` 한곳에 둔다. 기본 타입 생성기만으로 도메인 값을 만들지 않는다 | PBT-07 |
| NFR-04-D8 | 프레임워크의 축소 기능을 끄지 않는다 | PBT-08 |
| NFR-04-D9 | seed 는 고정값을 쓴다 (계획 Q2=A). 한곳에서 정하고, 환경 변수로 바꿔 실행할 수 있다. 실패 출력에 seed 와 축소된 입력이 나온다 | PBT-08 |
| NFR-04-D10 | PBT 는 일반 `flutter test` 에 포함되어 `tool/check.sh` 와 CI 에서 함께 실행된다. 따로 빼거나 건너뛰는 태그를 달지 않는다 | PBT-08 |
| NFR-04-D11 | 규칙마다 예시 기반 테스트가 있고, PBT 는 그 위에 더한다 | PBT-10 |

### NFR-05 유지보수성

| ID | 요구 | 측정 |
| --- | --- | --- |
| NFR-05-D1 | 새 fake · 생성기 · 조립 함수는 `test/helpers/` 에 둔다 | 파일 위치 |
| NFR-05-D2 | 기존 fake (`FakeAuthRepository`, `FakeApiClient`, `FakeSsdpDiscoveryService`, `FakeBackend`) 의 기본 동작을 바꾸지 않는다. 새 동작은 기본값이 기존 동작인 필드로 추가한다 | NFR-02-D2 |
| NFR-05-D3 | 테스트 이름은 기존 테스트처럼 한국어 문장으로, 무엇이 어떻게 되어야 하는지 적는다 (예: `재생 명령이 실패하면 PHONE_PLAY_FAILED 예외를 던진다`) | 코드 검토 |
| NFR-05-D4 | 테스트 묶음 (`group`) 은 `business-rules.md` 의 절 구성 (명령, 이벤트 변환, 폴링, 갭리스 등) 을 따르고, 규칙 ID 를 테스트 이름이나 주석에 적어 규칙과 테스트를 서로 찾을 수 있게 한다 | 코드 검토 |
| NFR-05-D5 | 운영 코드 변경은 `DlnaManager` 의 생성자 초기화 1곳으로 한정한다. 그 밖의 운영 코드 변경이 필요해지면 (예: `fake_async` 와 채널 조합이 안 됨, 버그 수정) 이유를 Code Generation 요약에 적는다 | `git diff --stat lib/` |

## 2. 범주별 평가

| 범주 | 평가 |
| --- | --- |
| 확장성 | 해당 없음. 부하 · 증가를 다루는 코드를 만들지 않는다 |
| 성능 | 앱 성능 요구 없음. 테스트 실행 시간만 해당 (NFR-03-D4) |
| 가용성 | 해당 없음. 운영되는 서비스가 없다 |
| 보안 | 보안 확장은 사용하지 않는다. 다만 아래 SEC 요구 2개를 둔다 |
| 신뢰성 | 테스트의 결정성 (NFR-03), 속성 테스트의 재현성 (NFR-04-D8 ~ D10) |
| 유지보수성 | NFR-05 |
| 사용성 | 해당 없음. UI 를 바꾸지 않는다 |

### 테스트 데이터 보안

| ID | 요구 | 측정 |
| --- | --- | --- |
| SEC-D1 | 테스트 코드와 fixture 에 실제 TIDAL 토큰 · 클라이언트 키 · 계정 · 서명된 CDN 주소를 넣지 않는다. 값은 `token-1`, `https://cdn.example.test/...` 같은 가짜 값을 쓴다 | 코드 검토, `config/tidal.json` 의 값이 `test/` 에 없는지 검색 |
| SEC-D2 | 가짜 기기 주소는 문서용 예약 대역 (`192.0.2.0/24`) 이나 `.test` 도메인을 쓴다. 실제 집 네트워크의 주소를 적지 않는다 | 코드 검토 |

## 3. 확장 규칙에서 나오는 요구

### Property-Based Testing

| 규칙 | 이 stage 의 요구 | 상태 |
| --- | --- | --- |
| PBT-09 | Dart 용 프레임워크를 선택하고 기술 스택 결정에 문서화, 의존성에 포함 | `tech-stack-decisions.md` D1 에서 결정. `pubspec.yaml` 반영은 Code Generation |
| PBT-08 | seed 정책 선택 | 고정 seed (NFR-04-D9) |

### Resiliency

이 unit 은 운영 경로에 새 외부 호출 · 저장소 · 배포 구성을 추가하지 않는다. RESILIENCY 규칙에서 이 stage 에 새로 생기는 요구는 없다. RESILIENCY-14 (복원력 테스트 방식) 질문과 RESILIENCY-15 (장애 대응 · COE 제안) 는 이 unit 의 NFR Design 에서 다룬다 (`unit-of-work.md`).

참고로 이 unit 의 테스트가 기존 복원력 동작을 고정한다: 스피커 무응답 3회 → `DLNA_UNREACHABLE` (DB-27), 탐색에서 스피커가 사라지면 폰 스피커로 전환 (DM-26), SOAP 실패 시 false · null 반환 (DM-06, DM-10).

## 4. 배정 NFR 대조 (NR-1)

| `unit-of-work-story-map.md` 에서 이 unit 에 배정된 NFR | 이 문서 |
| --- | --- |
| NFR-01 (Dart 4개 파일 80% 달성) | NFR-01-D1 ~ D4 |
| NFR-02 | NFR-02-D1 ~ D3 |
| NFR-03 | NFR-03-D1 ~ D5 |
| NFR-04 (Dart) | NFR-04-D1 ~ D11 |
| NFR-05 | NFR-05-D1 ~ D5 |
