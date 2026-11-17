# NFR Design 계획 - dart-playback-tests

**이 stage 가 정하는 것**: NFR Requirements 의 테스트 품질 요구 (결정성, 속도, 재현성, 유지보수성) 를 **테스트 코드의 패턴과 구성 요소** 로 옮긴다. 그리고 `unit-of-work.md` 가 이 unit 에 배정한, 프로젝트 전체에 한 번만 정하는 복원력 항목 두 가지 (RESILIENCY-14 질문, RESILIENCY-15 의 가벼운 장애 대응 절차 제안) 를 다룬다.

## 실행 단계

- [x] 1. NFR Requirements 산출물 읽기 (`nfr-requirements.md` 의 30개 항목, `tech-stack-decisions.md` 의 결정 8개)
- [x] 2. 아래 질문에 대한 답변 수집 · 모호성 분석
- [x] 3. `aidlc-docs/construction/dart-playback-tests/nfr-design/nfr-design-patterns.md` 생성
  - [x] 3.1 결정성 패턴: 가짜 시간 안에서의 비동기 진행, 채널 가로채기의 설치 · 해제, 테스트 간 격리
  - [x] 3.2 검증 패턴: 이벤트 기록, 호출 기록, 순서 단언, 규칙 ID 표기
  - [x] 3.3 속성 테스트 패턴: 생성기 구성, 모델 비교 (상태 기반), seed 설정, 실행 횟수
  - [x] 3.4 조립 패턴: 반복되는 준비 (원격 스피커가 선택된 `DlnaManager`, 재생 중인 `DlnaBackend`) 를 함수로
  - [x] 3.5 복원력: RESILIENCY-14 답변에 따른 테스트 방식, RESILIENCY-15 의 가벼운 장애 대응 · 오류 교정 절차 제안
  - [x] 3.6 NFR Requirements 항목별 대응 표 (ND-1)
- [x] 4. `aidlc-docs/construction/dart-playback-tests/nfr-design/logical-components.md` 생성: 테스트 지원 구성 요소 (파일, 책임, 서로의 관계), 인프라 구성 요소 해당 없음 근거
- [x] 5. 검증: `nfr-requirements.md` 의 모든 항목에 대응 패턴 또는 구성 요소가 있는지

## 질문

각 질문의 `[Answer]:` 뒤에 선택지 문자를 적어 주세요.

## Question 1: 복원력 테스트 방식 (Resiliency Testing Approach)
복원력 방식 (failover, 복구) 은 어떻게 검증합니까?

참고: 이 앱에는 서버가 없어 리전 장애 조치 · 재해 복구 훈련의 대상이 없습니다. 이 앱의 "복구" 는 기기 안의 동작입니다 (스피커 무응답 → 오류 알림, 스피커가 사라짐 → 폰 스피커로 전환, 주소 만료 → 재발급). 이 가운데 Dart 쪽 동작은 이번 자동 테스트가 고정합니다 (DB-27, DM-26, DB-48). 실기기에서만 확인되는 부분 (실제 스피커 전원 끄기, Wi-Fi 끊기) 은 자동 테스트 범위 밖입니다.

A) 기존 DR 테스트 / game day / 카오스 엔지니어링 관행 사용 — 참조 자료를 알려 주십시오. AI-DLC 가 그에 맞는 테스트 시나리오를 문서화합니다.

B) 관행 없음 — AI-DLC 가 도입할 DR 테스트 일정과 카오스 실험 계획을 제안. (권장: 이 앱에 맞춰 "실기기 장애 상황 점검표" 로 제안합니다. 스피커 전원 끄기 · Wi-Fi 끊기 · 오래 일시정지 뒤 재개 같은 5 ~ 6개 상황과 기대 동작을 적고, 정해진 일정 없이 렌더러를 새로 시험할 때 함께 해 보는 선택 항목으로 둡니다. 결과는 기존 `docs/dlna-compat.md` 에 적습니다)

C) Operations phase 로 미룸 — 테스트 시나리오는 지금 정리하고, 실행은 Operations 에서. (참고: 실행 계획에서 Operations stage 는 모두 SKIP 입니다)

X) Other (describe after [Answer]: tag below)

[Answer]: B (사용자 지시 "추천으로 진행해줘" 에 따라 권장안 기입)

## Question 2 (복원력 패턴)
요구사항에서 장애 대응은 "정식 프로세스 없음 → 가벼운 장애 대응 · 오류 교정 (COE) 절차를 제안" 으로 정했습니다 (RESILIENCY-15, 후속 Q10=B). 문제가 생겼을 때의 기록을 어디에 남길까요?

A) 저장소 안의 문서 - `docs/incidents/` 에 문제마다 파일 하나 (증상, 원인, 수정 커밋, 추가한 테스트, 재발 방지). 기존 커밋 메시지 방식 (`fix: 실기기에서 ...`) 과 `docs/dlna-compat.md` 를 그대로 쓰면서 원인 분석만 따로 남긴다. 코드와 함께 버전 관리된다 (권장)

B) GitHub Issues - 문제마다 이슈 하나, 라벨로 구분, 수정 커밋에서 이슈를 참조한다. 저장소 밖에 기록이 남는다

C) 별도 기록 없음 - 커밋 메시지와 `docs/dlna-compat.md` 만으로 충분하다. 절차 문서는 "버그를 고칠 때 실패 테스트를 먼저 추가한다" 한 줄만 둔다

X) Other (please describe after [Answer]: tag below)

[Answer]: A (사용자 지시 "추천으로 진행해줘" 에 따라 권장안 기입)

## 질문하지 않은 범주와 이유

- **확장성 패턴**: 부하 · 증가를 다루는 코드가 없다 (`nfr-requirements.md` 2절: 해당 없음)
- **성능 패턴**: 기준과 조정 방법이 정해져 있다 (NFR-03-D4: 30초, `tech-stack-decisions.md` D8: 속성당 100회에서 시작해 필요하면 상태 기반 속성부터 줄임)
- **보안 패턴**: 보안 확장을 쓰지 않는다. 테스트 데이터 요구 (SEC-D1, SEC-D2) 는 가짜 값 규칙으로 충분해 고를 것이 없다
- **논리 컴포넌트 (queue, cache, circuit breaker 등)**: 인프라 구성 요소를 추가하지 않는다. 이 unit 의 구성 요소는 모두 테스트 지원 코드이고 Application Design 에서 정했다
- **결정성 · 검증 · 속성 테스트 패턴의 세부**: 도구가 정해져 (`fake_async`, 테스트 바인딩, `kiri_check`) 사용자 선택이 필요한 지점이 없다. 도구 조합이 안 맞는 경우의 대안은 `tech-stack-decisions.md` 에 적어 두었다
