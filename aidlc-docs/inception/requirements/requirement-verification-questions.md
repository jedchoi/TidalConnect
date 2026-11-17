# 요구사항 확인 질문 (Requirements Clarification Questions)

아직 이번 작업의 목표 (만들거나 고칠 것) 를 받지 못했습니다. 아래 질문의 `[Answer]:` 뒤에 선택지 문자 (필요하면 설명) 를 적어 주세요. 후보는 Reverse Engineering 에서 찾은 내용 (`aidlc-docs/inception/reverse-engineering/code-quality-assessment.md` 등) 을 근거로 만들었습니다.

## Question 1
이번 작업의 주된 목표는 무엇입니까?

A) 새 기능 추가 (내용은 X 처럼 아래에 설명)

B) Flutter 3.47+ 대비: `material.dart` 폐기 예정 대응 (material_ui 이전) 과 Flutter 버전 상향

C) 테스트 보강: `PhoneBackend`, `DlnaBackend`, `DlnaManager`, `WaveAudioHandler`, 프록시, `PlaybackCore` 테스트 추가

D) 보안 · 배포 정리: release 서명, cleartext 허용 범위 축소, `clientSecret` 처리, 빈 `catch` 정리

E) 기존 기능 개선 · 버그 수정 (내용을 아래에 설명)

X) Other (please describe after [Answer]: tag below)

[Answer]: C

## Question 2
Question 1 의 목표를 구체적으로 적어 주세요. (원하는 동작, 대상 화면 · 기기, 현재 문제 증상 등. B · C · D 를 그대로 진행하려면 "선택지대로" 라고 적어도 됩니다)

A) 선택지 설명대로 진행 (추가 설명 없음)

X) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 3
이번 작업의 성공 기준은 무엇입니까?

A) `tool/check.sh` 전체 통과 + 실기기 (폰 · DLNA 렌더러) 에서 동작 확인

B) `tool/check.sh` 전체 통과만 (실기기 확인은 생략)

C) 실기기 동작 확인이 핵심, 자동 테스트는 가능한 범위만

X) Other (please describe after [Answer]: tag below)

[Answer]: B

## Question 4
이 앱은 어떤 용도로 쓰입니까? (요구사항 깊이와 위험 판단에 사용)

A) 개인용 · 학습용 (본인 기기에서만 사용)

B) 지인 · 소수에게 APK 로 배포

C) 스토어 (Google Play) 배포 예정

X) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 5
기존 동작 중 이번 작업에서 절대 바뀌면 안 되는 것이 있습니까?

A) 재생 구조 전체 (`PlayerManager` 단일 출처, 두 백엔드 인터페이스, `PlaybackCore` 소유 구조) 는 유지

B) 특별한 제약 없음 (필요하면 구조 변경 가능)

X) Other (please describe after [Answer]: tag below)

[Answer]: B

## Question 6: 보안 확장 (Security Extensions)
이 프로젝트에 보안 확장 규칙을 강제할까요?

A) 예 — 모든 SECURITY 규칙을 차단성 제약으로 강제 (운영 수준 애플리케이션에 권장)

B) 아니요 — 모든 SECURITY 규칙 건너뜀 (PoC, 프로토타입, 실험 프로젝트에 적합)

X) Other (please describe after [Answer]: tag below)

[Answer]: B

## Question 7: 복원력 확장 (Resiliency Extensions)
이 프로젝트에 복원력 기준 (resiliency baseline) 을 적용할까요?

**이 확장이 하는 일.** 활성화하면 복원력 있는 시스템을 만들기 위한 **방향 제시용 · 설계 단계 모범 사례** 묶음을 적용합니다. 이 모범 사례는 **AWS Well-Architected Framework (Reliability Pillar)** 와 복원력 검토 지침에서 가져온 것입니다. 요구사항 · 설계 · 코드를 장애 허용 (fault tolerance), 고가용성, 관측 가능성 (observability), 복구 가능성 쪽으로 이끌며, 비즈니스 목표, 변경 관리, 관측 가능성, 고가용성, 재해 복구, 지속적 개선에 걸친 15개 실천 영역을 다룹니다.

**이 확장이 하지 않는 일.** 활성화해도 워크로드가 운영 환경에 바로 투입 가능한 상태 (production-ready) 가 되지는 **않으며**, 어떤 가용성 · RTO · RPO 목표도 인증하거나 보장하지 않습니다. 좋은 복원력 결정을 초기에 잡아 주는 **출발점**일 뿐이며, 완성된 시스템에 대한 정식 **AWS Well-Architected Review** 를 대신하지 않습니다.

결과물은 이후 보완 · 검증해 나갈, 근거 있는 **복원력 태세 초안**으로 다루십시오. 완성된 결과나 운영 인증을 받은 결과가 아닙니다.

A) 예 — 복원력 기준을 방향 제시용 모범 사례 및 설계 단계 지침으로 적용 (비즈니스 핵심 워크로드에 권장. 운영 개시 전에 검증 · 강화할 수 있는, 근거 있는 출발점)

B) 아니오 — 복원력 기준 생략 (신뢰성보다 빠른 반복이 중요한 PoC, 프로토타입, 실험 프로젝트에 적합)

X) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 8: 속성 기반 테스트 확장 (Property-Based Testing Extension)
이 프로젝트에 속성 기반 테스트 (PBT) 규칙을 강제할까요?

A) 예 — 모든 PBT 규칙을 차단성 제약으로 강제 (비즈니스 로직, 데이터 변환, 직렬화, 상태를 가진 구성요소가 있는 프로젝트에 권장)

B) 부분 — 순수 함수와 직렬화 왕복 (round-trip) 에만 PBT 규칙 강제 (알고리즘 복잡도가 낮은 프로젝트에 적합)

C) 아니요 — 모든 PBT 규칙 건너뜀 (단순 CRUD 애플리케이션, UI 전용 프로젝트, 중요한 비즈니스 로직이 없는 얇은 통합 계층에 적합)

X) Other (please describe after [Answer]: tag below)

[Answer]: A
