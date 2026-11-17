# Unit of Work 요구사항 매핑 (Unit of Work Story Map)

User Stories stage 를 SKIP 했으므로 스토리 ID 가 없다. 대신 `aidlc-docs/inception/requirements/requirements.md` 의 FR · NFR 을 unit 에 매핑한다.

## 기능 요구사항

| FR | 내용 | unit | 비고 |
| --- | --- | --- | --- |
| FR-01 | `PhoneBackend` 테스트 | `dart-playback-tests` | |
| FR-02 | `DlnaBackend` 테스트 | `dart-playback-tests` | |
| FR-03 | `DlnaManager` 테스트 | `dart-playback-tests` | |
| FR-04 | `WaveAudioHandler` 테스트 | `dart-playback-tests` | |
| FR-05 | `TidalStreamProxyServer` 테스트 | `android-native-tests` | "CDN URL 없음 400" 항목은 Functional Design 에서 정정 |
| FR-06 | `PlaybackCore` 테스트 | `android-native-tests` | `PlaybackCommandRouter` 로 검증, Android 연결부 제외 |
| FR-07 | 테스트 용이성을 위한 운영 코드 변경 | `dart-playback-tests` (Dart 부분), `android-native-tests` (Kotlin 부분) | 언어별로 나뉨 |
| FR-08 | 발견 버그 수정 | 발견한 unit (`dart-playback-tests` 또는 `android-native-tests`) | 계획 Q4=A |
| FR-09 | CI 커버리지 검사 · APK 산출물 | `ci-quality-gate` | |

## 비기능 요구사항

| NFR | 내용 | unit | 비고 |
| --- | --- | --- | --- |
| NFR-01 | 커버리지 목표 | `dart-playback-tests` (Dart 4개 파일 80% 달성), `android-native-tests` (동작 목록 충족), `ci-quality-gate` (자동 검사) | |
| NFR-02 | `tool/check.sh` 통과 | 세 unit 모두 | 최종 확인은 `ci-quality-gate` 와 Build and Test |
| NFR-03 | 테스트 결정성 · 속도 | `dart-playback-tests`, `android-native-tests` | |
| NFR-04 | 속성 기반 테스트 | `dart-playback-tests` (Dart), `android-native-tests` (Kotlin) | `ci-quality-gate` 는 NFR Requirements 에서 적용 여부 판단 |
| NFR-05 | 유지보수성 (`test/helpers/` 방식, 줄 길이 120) | `dart-playback-tests` | |

## 복원력 결정 사항

| 항목 | unit |
| --- | --- |
| RESILIENCY-04 CI/CD (APK 빌드 · 업로드 단계) | `ci-quality-gate` |
| RESILIENCY-14 복원력 테스트 방식 질문 | `dart-playback-tests` 의 NFR Design (프로젝트 전체에 한 번) |
| RESILIENCY-15 가벼운 장애 대응 · COE 제안 | `dart-playback-tests` 의 NFR Design (프로젝트 전체에 한 번) |

## 배정 확인

- FR-01 ~ FR-09: 모두 하나 이상의 unit 에 배정됨
- NFR-01 ~ NFR-05: 모두 하나 이상의 unit 에 배정됨
- 요구사항이 없는 unit: 없음
- `application-design.md` 의 컴포넌트는 모두 unit 의 포함 파일에 들어 있음 (`unit-of-work.md`)
