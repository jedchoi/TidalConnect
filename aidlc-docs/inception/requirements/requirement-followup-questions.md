# 요구사항 후속 질문 (Requirements Follow-up Questions)

1차 답변 요약: 목표 = 테스트 보강 (C, 선택지대로), 성공 기준 = `tool/check.sh` 통과만 (B), 용도 = 개인용 (A), 구조 제약 없음 (B), 보안 확장 = 아니요, 복원력 확장 = 예, PBT 확장 = 예 (전체 강제).

아래는 (1) 범위를 좁히기 위한 질문과 (2) 복원력 확장 규칙 (RESILIENCY-02 · 03 · 04 · 08 · 15) 이 Requirements 단계에서 반드시 묻도록 정한 질문입니다. 이 앱은 서버 · 클라우드 배포가 없는 개인용 Android 앱이라 대부분 N/A 가 자연스럽지만, 규칙상 직접 선택을 받아야 합니다.

## Question 1
테스트를 보강할 대상은 어디까지입니까?

A) 6개 모두: `PhoneBackend`, `DlnaBackend`, `DlnaManager`, `WaveAudioHandler` (Dart) + `TidalStreamProxyServer`, `PlaybackCore` (Kotlin)

B) Dart 4개만 (`PhoneBackend`, `DlnaBackend`, `DlnaManager`, `WaveAudioHandler`), Kotlin 은 이번에 제외

C) DLNA 경로 우선: `DlnaBackend`, `DlnaManager`, `TidalStreamProxyServer`

X) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 2
테스트하기 어려운 코드 (싱글톤, 플랫폼 채널, 실제 소켓 · 시간 의존) 를 만났을 때 운영 코드를 얼마나 고쳐도 됩니까?

A) 테스트를 위한 최소 변경만 허용 (생성자 주입 · 인터페이스 추출 · 시계 · 타이머 주입 등), 동작 변경 없음

B) 테스트 중 발견한 버그 수정까지 허용 (수정마다 별도 커밋 · 기록)

C) 운영 코드 변경 금지, 테스트만 추가 (어려운 부분은 테스트하지 않음)

X) Other (please describe after [Answer]: tag below)

[Answer]: B

## Question 3
"테스트 보강" 의 완료 기준으로 수치 목표를 둘까요?

A) 수치 없음: 대상 컴포넌트마다 공개 메서드 · 이벤트 처리 · 오류 경로를 테스트로 덮으면 완료

B) 라인 커버리지 측정 도입 (`flutter test --coverage`) 후 대상 파일 커버리지 목표 지정 (목표치를 아래에 적어 주세요)

X) Other (please describe after [Answer]: tag below)

[Answer]: B

## Question 4: RTO/RPO 목표와 재해 복구 전략 (RTO/RPO Goals and Disaster Recovery Strategy)
목표 복구 시간 (RTO) 과 목표 복구 시점 (RPO) 은 어느 정도입니까? 이 값에 따라 알맞은 재해 복구 전략과 인프라 이중화 수준이 정해집니다.

A) RPO/RTO: 수 시간 — Backup & Restore 전략. 최저 비용 ($). 데이터는 백업, 서비스는 미배포. 장애 시 IaC 로 재배포하고 백업에서 복원. 핵심이 아닌 워크로드에 적합.

B) RPO/RTO: 수십 분 — Pilot Light 전략. 비용: $$. 데이터는 실시간 유지, 서비스는 대기. 인프라는 배포되어 있으나 실행되지 않으며, failover 시 확장. 중요한 워크로드에 적합.

C) RPO/RTO: 수 분 — Warm Standby 전략. 비용: $$$. 데이터는 실시간 유지, 서비스는 축소 용량으로 실행. failover 시 확장. 비즈니스 핵심 애플리케이션에 적합.

D) RPO/RTO: 거의 실시간 — Multi-site Active/Active 전략. 최고 비용 ($$$$). 데이터 실시간 유지, 여러 리전에서 서비스 동시 운영. 미션 크리티컬, 무중단 요구사항에 적합.

E) N/A — 단일 리전 배포로 충분, 리전 간 DR 불필요. 한 리전 안의 멀티 존 가용성에 의존.

X) Other (please describe after [Answer]: tag below)

[Answer]: E

## Question 5: 변경 관리 프로세스 (Change Management Process)
이 워크로드의 운영 환경 변경은 어떻게 관리해야 합니까? AI-DLC 는 프로세스를 새로 만들지 않고 답변에 맞춰 설계합니다.

A) 기존 조직 변경 관리 프로세스 사용 — 이름 / 도구를 알려 주십시오 (예: ServiceNow, Jira Change, 사내 CAB). AI-DLC 가 이를 참조하고, 배포 산출물이 그 프로세스 (변경 기록, 승인 관문) 에 맞도록 합니다.

B) 아직 정식 프로세스 없음 — AI-DLC 가 팀이 도입할 가벼운 변경 관리 프로세스 (변경 기록 + 승인 + 롤백 메모) 를 제안.

C) N/A — 이 워크로드는 정식 변경 관리 대상에서 제외 (예: 내부 도구). 제외 근거를 문서화.

X) Other (describe after [Answer]: tag below)

[Answer]: C

## Question 6: CI/CD 및 배포 도구 (CI/CD and Deployment Tooling)
이 워크로드는 어떤 CI/CD 도구와 배포 프로세스를 사용해야 합니까? (참고: 현재 GitHub Actions `.github/workflows/check.yml` 이 `tool/check.sh` 를 실행)

A) 기존 CI/CD 파이프라인 사용 — 도구를 알려 주십시오 (예: GitHub Actions, GitLab CI, Jenkins, CodePipeline). AI-DLC 가 이와 호환되는 산출물을 만듭니다.

B) 파이프라인 없음 — AI-DLC 가 선택된 IaC 와 런타임에 맞는 CI/CD 파이프라인 정의를 제안.

X) Other (describe after [Answer]: tag below)

[Answer]: B

## Question 7: 롤백 방식 (Rollback Mechanism)
실패한 운영 배포는 어떻게 롤백해야 합니까? (참고: 개인용 APK 라면 "이전 APK 재설치" 가 A 에 해당)

A) 이전 IaC / 산출물 버전 재배포 (버전 고정 롤백)

B) Blue/green 으로 이전 환경으로 되돌려 전환

C) 상태 / 지표 악화 시 canary 자동 롤백

D) 데이터베이스를 고려한 롤백 필요 (스키마 / 데이터 마이그레이션 되돌리기) — 별도 명시적 설계 대상으로 표시

E) 조직의 기존 롤백 절차 사용 — 참조 자료를 알려 주십시오

X) Other (describe after [Answer]: tag below)

[Answer]: B

## Question 8: 배포 방식 (Deployment Style)
이 워크로드의 위험 수준에 허용 가능한 배포 전략은 무엇입니까?

A) Direct / in-place (최저 비용, 영향 범위 (blast radius) 최대) — 핵심이 아닌 워크로드에 허용

B) Rolling (인스턴스를 점진적으로 교체)

C) Blue/green (무중단 전환, 비용 높음)

D) Canary (자동 롤백을 갖춘 점진적 트래픽 이동)

X) Other (describe after [Answer]: tag below)

[Answer]: A

## Question 9: 리전 구성 (Regional Topology)
이 워크로드에 멀티 리전 배포가 필요합니까, 아니면 멀티 존 이중화를 갖춘 단일 리전으로 충분합니까? (참고: 서버가 없는 기기 앱이면 X 에 "N/A - 기기 앱" 이라고 적어도 됩니다)

A) 단일 리전, 멀티 존 — 존 장애는 견디지만 리전 전체 장애는 견디지 못함. 비용 낮음. (RTO/RPO 선택지 A/B/E 와 대응.)

B) 멀티 리전 active-passive — failover 로 리전 장애를 견딤. 비용 높음. (리전 간 Warm Standby / Pilot Light 와 대응.)

C) 멀티 리전 active-active — 중단 없이 리전 장애를 견딤. 최고 비용. (Active/Active 와 대응.)

X) Other (describe after [Answer]: tag below)

[Answer]: A

## Question 10: 장애 대응 프로세스 (Incident Response Process)
이 워크로드의 운영 장애는 어떻게 처리합니까?

A) 기존 장애 대응 프로세스 사용 — 참조 자료를 알려 주십시오 (예: PagerDuty 런북, 사내 IR / 당직 (on-call) 프로세스). AI-DLC 가 경보와 런북을 그에 맞춥니다.

B) 정식 프로세스 없음 — AI-DLC 가 도입할 가벼운 장애 대응 및 오류 교정 (Correction of Errors, COE) 프로세스를 제안.

X) Other (describe after [Answer]: tag below)

[Answer]: B
