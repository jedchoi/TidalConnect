# 요구사항 2차 후속 질문 (Requirements Follow-up Questions 2)

후속 답변 요약: 대상 6개 모두 (A), 발견 버그 수정 허용 (B), 커버리지 목표 도입 (B), RTO/RPO N/A (E), 변경 관리 대상 제외 (C), CI/CD "파이프라인 없음 → 제안" (B), 롤백 blue/green (B), 배포 direct (A), 단일 리전 멀티 존 (A), 장애 대응 가벼운 COE 제안 (B).

아래 3개 답변이 비어 있거나 서로 맞지 않아 확인이 필요합니다.

**참고 - 현재 Dart 라인 커버리지 측정값** (2026-11-17, `flutter test --coverage`, 95개 테스트 통과):

| 파일 | 커버리지 |
| --- | --- |
| 전체 (테스트가 import 한 49개 파일 기준) | 42.0% (1376/3274) |
| `lib/features/player/data/backends/phone_backend.dart` | 0% (0/61) |
| `lib/features/player/data/backends/dlna_backend.dart` | 0% (0/178) |
| `lib/features/dlna/data/dlna_manager.dart` | 15.4% (20/130) |
| `lib/features/player/data/wave_audio_handler.dart` | 측정 안 됨 (어떤 테스트도 import 하지 않음) |

Kotlin 은 커버리지 도구가 없습니다 (도입하려면 JaCoCo 를 Gradle 에 추가해야 함).

## Question 1
1차 후속 Q3 에서 커버리지 목표를 고르셨지만 목표치가 비어 있습니다. 대상 파일의 목표를 정해 주세요.

A) Dart 대상 4개 파일 각각 라인 커버리지 80% 이상, Kotlin 은 수치 없이 공개 동작 · 오류 경로 테스트로 판단

B) Dart 대상 4개 파일 각각 70% 이상, Kotlin 은 수치 없이 판단

C) Dart 대상 4개 파일 80% 이상 + Kotlin 에 JaCoCo 도입해 `TidalStreamProxyServer` · `PlaybackCore` 70% 이상

X) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 2
1차 후속 Q6 에서 "파이프라인 없음 → 새로 제안" (B) 을 고르셨지만, 저장소에는 이미 GitHub Actions (`.github/workflows/check.yml`, 푸시 · PR 마다 `tool/check.sh` 실행) 가 있습니다. 어느 쪽입니까?

A) 기존 GitHub Actions 를 그대로 사용 (필요하면 커버리지 점검 단계만 추가)

B) 기존 GitHub Actions 를 바탕으로 배포 (APK 빌드 · 산출물 업로드) 단계까지 새로 제안

X) Other (please describe after [Answer]: tag below)

[Answer]: B

## Question 3
1차 후속 Q7 (롤백 = blue/green 전환) 과 Q8 (배포 = direct / in-place) 이 서로 맞지 않습니다. blue/green 은 두 운영 환경을 두고 트래픽을 전환하는 방식이라, 서버 없이 기기에 APK 를 설치하는 이 앱에는 전환할 환경이 없습니다. 롤백 방식을 다시 골라 주세요.

A) 이전 버전 APK 재설치 (버전 고정 롤백, git 태그 · 커밋 기준으로 다시 빌드)

B) git revert 후 다시 빌드 · 설치

X) Other (please describe after [Answer]: tag below)

[Answer]: B
