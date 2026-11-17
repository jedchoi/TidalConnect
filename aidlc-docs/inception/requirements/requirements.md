# 요구사항 (Requirements)

## 의도 분석 요약 (Intent Analysis)

| 항목 | 내용 |
| --- | --- |
| 사용자 요청 | 테스트가 없는 재생 · DLNA 핵심 컴포넌트 6개에 테스트를 보강한다 (1차 Q1=C, Q2=A, 후속 Q1=A) |
| 요청 유형 | Enhancement (테스트 보강) + 테스트 중 발견한 버그의 Bug Fix 허용 (후속 Q2=B) |
| 범위 추정 | Multiple Components: Dart 4개 파일, Kotlin 2개 파일, CI 설정 1개 |
| 복잡도 추정 | Moderate: 싱글톤 (`DlnaManager.instance`), 플랫폼 채널 (`TidalSdkNativeBridge`), 주기 타이머 (`Timer.periodic`), 로컬 HTTP 서버, 프로세스 범위 `object PlaybackCore` 를 테스트에서 대체해야 함 |
| 요구사항 깊이 | Standard |
| 앱 용도 | 개인용 · 학습용, 본인 기기에서만 사용 (1차 Q4=A) |

## 기준값 (Baseline, 2026-11-17 측정)

`flutter test --coverage` 결과 95개 테스트 통과, 라인 커버리지:

| 대상 | 라인 커버리지 |
| --- | --- |
| `lib/features/player/data/backends/phone_backend.dart` | 0% (0/61) |
| `lib/features/player/data/backends/dlna_backend.dart` | 0% (0/178) |
| `lib/features/dlna/data/dlna_manager.dart` | 15.4% (20/130) |
| `lib/features/player/data/wave_audio_handler.dart` | 측정 안 됨 (테스트가 import 하지 않음) |
| `TidalStreamProxyServer.kt`, `PlaybackCore.kt` | 측정 도구 없음, 테스트 없음 |

## 기능 요구사항 (Functional Requirements)

### FR-01: `PhoneBackend` 테스트
`lib/features/player/data/backends/phone_backend.dart` 에 대해 다음을 자동 테스트로 검증한다:
- `play`, `pause`, `resume`, `seek`, `stop`, `setAudioQuality`, `setNext` 가 대응하는 MethodChannel 메서드 (`playTrack`, `pauseTrack`, `resumeTrack`, `seekTrack`, `stopTrack`, `setAudioQuality`, `setNextTrack`) 를 올바른 인자로 호출한다
- EventChannel `player_events` 의 `state`, `position`, `transition`, `ended`, `error` 이벤트가 각각 `BackendStateChanged`, `BackendPositionChanged`, `BackendTrackStarted` (+ `StreamQuality`), `BackendTrackEnded`, `BackendError` 로 변환된다 (변환 규칙은 `aidlc-docs/inception/reverse-engineering/api-documentation.md` C절 표 기준)
- `play` · `pause` · `resume` 의 네이티브 호출이 실패하면 `PlaybackException(code, message)` 로 전달된다. `seek` · `stop` · `setNext` · `setAudioQuality` 는 실패해도 예외를 내지 않는다 (2026-11-17 정정: Functional Design 계획 Q2=A, 지금 동작을 규칙으로 확정)
- `isCancelled` 가 true 가 된 재생 요청은 이후 상태를 바꾸지 않는다

### FR-02: `DlnaBackend` 테스트
`lib/features/player/data/backends/dlna_backend.dart` 에 대해 다음을 검증한다:
- 재생 흐름: 스트림 등록 (`registerTrackStream`) → 프록시 URL 로 `SetAVTransportURI` → `Play` 순서로 호출된다
- 1초 주기 폴링 (`GetTransportInfo`, `GetPositionInfo`) 결과가 상태 · 위치 이벤트로 변환된다
- 곡 끝 판정: 남은 시간이 종료 허용치 (`_endTolerance` = 3초) 안에서 정지 상태가 되면 `BackendTrackEnded` 가 1회만 발생한다
- 폴링이 연속 3회 (`_maxFailures`) 실패하면 폴링이 멈추고 `BackendStateChanged(playing: false)` 와 `BackendError('DLNA_UNREACHABLE', ...)` 가 발생한다
- `setNext` 가 `SetNextAVTransportURI` 를 호출하고, 같은 스트림 URL 판정 (`_sameStreamUrl`) 이 동작한다
- `stop` 이후 폴링 타이머가 해제되고 스트리밍 잠금 (`setStreamingLock(false)`) 이 풀린다
- `registerTrackStream` 이 `NO_WIFI` 오류를 돌려주면 `PlaybackException` 으로 전달된다

### FR-03: `DlnaManager` 테스트
`lib/features/dlna/data/dlna_manager.dart` 에 대해 다음을 검증한다:
- 기기 탐색 (`discoverDevices`) 결과 반영, 기기 선택 · 선택 해제, 선택한 기기 UDN 의 저장 (`selected_speaker_udn`) 과 재시작 후 복원
- 재생 제어 (`playOnSelectedDevice`, `pauseCurrent`, `resumeCurrent`, `seek`, `stopCurrent`, `setNextOnSelectedDevice`), 볼륨 (`fetchVolume`, `setVolume` 의 0~100 범위 제한), 상태 · 위치 조회 (`getTransportState`, `syncPosition` → `DlnaPosition`) 가 SOAP 클라이언트 결과를 올바르게 전달하고, SOAP 실패 (null · false) 를 처리한다

### FR-04: `WaveAudioHandler` 테스트
`lib/features/player/data/wave_audio_handler.dart` 에 대해 다음을 검증한다:
- 잠금화면 · 알림 · 블루투스 명령 (play, pause, stop, skipToNext, skipToPrevious, seek) 이 `PlayerManager` 의 대응 명령 (`resume`, `pause`, `skipToNext`, `skipToPrevious`, `seekTo` 등) 으로 전달된다
- `PlayerManager` 상태 변화가 audio_service 의 `playbackState` · `mediaItem` 으로 반영된다
- 선택된 출력 기기 (`DlnaManager.selectedDeviceNotifier`) 가 바뀌면 재생 정보가 다시 알려지고, 원격 스피커 선택 시 원격 볼륨 명령 (`androidAdjustRemoteVolume`, `androidSetRemoteVolume`) 이 `PlayerManager` 의 볼륨 명령으로 전달된다

### FR-05: `TidalStreamProxyServer` 테스트 (Kotlin)
`android/app/src/main/kotlin/com/example/tidal_connect_lite/TidalStreamProxyServer.kt` 에 대해 다음을 검증한다:
- `/ping` 은 200 `pong`, 그 밖의 경로는 404
- `/audio/{token}.{ext}`: 미등록 토큰 404, `allowedHost` 와 다른 요청 IP 403, CDN URL 없음 400, 스트림 갱신 실패 403 `Stream expired`
- HEAD 요청은 본문 없이 길이 · 타입 헤더를 돌려준다
- 직접 CDN 경로가 Range 헤더를 업스트림에 전달한다
- 토큰 등록이 16자 토큰과 mime 에 맞는 확장자를 가진 URL 을 만든다

### FR-06: `PlaybackCore` 테스트 (Kotlin)
`android/app/src/main/kotlin/com/example/tidal_connect_lite/PlaybackCore.kt` 에 대해 다음을 검증한다:
- `onMethodCall` 이 각 메서드 이름을 올바른 동작으로 보내고, 정해진 반환 맵 (`{status: ...}`) 을 돌려준다
- 플레이어가 초기화되지 않았을 때 `runPlayerAction` 이 오류를 돌려준다
- 알 수 없는 메서드는 `notImplemented` 로 응답한다
- `registerTrackStream` 이 Wi-Fi 가 없을 때 `NO_WIFI` 오류를 돌려준다

### FR-07: 테스트 용이성을 위한 운영 코드 변경
- 테스트에 필요한 경우에만 운영 코드에 대체 지점을 만든다: 생성자 주입, 인터페이스 추출, 시계 · 타이머 주입, 채널 대체
- 이 변경은 앱의 외부 동작 (화면, 재생 결과, 채널 계약) 을 바꾸지 않는다
- 구조 변경 제약은 없다 (1차 Q5=B). 단, `PlayerManager` 가 재생 상태의 단일 출처라는 원칙 (CLAUDE.md) 은 유지한다

### FR-08: 발견 버그 수정
- 테스트 작성 중 발견한 버그는 수정할 수 있다 (후속 Q2=B)
- 버그마다: 실패하는 테스트를 먼저 추가하고, 수정은 별도 커밋으로 하며, 증상 · 원인 · 수정을 Code Generation 산출물 요약에 기록한다

### FR-09: CI 에 커버리지 점검과 APK 빌드 단계 추가
기존 GitHub Actions (`.github/workflows/check.yml`) 를 바탕으로 다음을 추가한다 (2차 Q2=B):
- NFR-01 의 커버리지 기준을 CI 에서 검사하는 단계 (기준 미달이면 실패)
- debug APK 빌드 후 workflow 산출물 (artifact) 로 업로드하는 단계
- 로컬 `tool/check.sh` 와 CI 의 점검 내용이 같도록 유지한다 (CLAUDE.md 원칙)

## 비기능 요구사항 (Non-Functional Requirements)

### NFR-01: 커버리지 목표
- Dart 대상 4개 파일 (`phone_backend.dart`, `dlna_backend.dart`, `dlna_manager.dart`, `wave_audio_handler.dart`) 은 각각 라인 커버리지 80% 이상 (`flutter test --coverage` 기준, 2차 Q1=A)
- Kotlin 2개 파일은 수치 목표 없음. FR-05 · FR-06 에 적은 공개 동작과 오류 경로가 모두 테스트되면 충족

### NFR-02: 점검 통과
- `tool/check.sh` (format, `flutter analyze --fatal-infos`, `flutter test`, Kotlin 단위 테스트) 가 로컬과 CI 에서 모두 통과한다 (1차 Q3=B)
- 실기기 확인은 완료 기준에 넣지 않는다

### NFR-03: 테스트 결정성 · 속도
- 새 테스트는 실제 네트워크, 실제 TIDAL 계정, 실기기, 실제 시간 대기 (wall-clock sleep) 에 의존하지 않는다. 시간 의존 로직은 가짜 시계 · 타이머 (예: `fake_async`) 로 검증한다
- 같은 코드에서 10회 연속 실행해 결과가 모두 같아야 한다 (flaky 0건)
- 새 Dart 테스트 전체가 `flutter test` 실행 시간을 30초 넘게 늘리지 않는다 (현재 전체 약 4초)
- `TidalStreamProxyServer` 테스트는 루프백 주소 (127.0.0.1) 와 임시 포트만 쓴다 (고정 포트 8765 충돌 방지)

### NFR-04: 속성 기반 테스트 (PBT 확장)
- PBT 확장 전체 강제 (1차 Q8=A). 대상 컴포넌트의 변환 · 상태 로직 (예: 이벤트 맵 → `BackendEvent` 변환, DLNA 시간 문자열 ↔ `Duration`, 폴링 상태 기계, 프록시 토큰 · URL 생성) 은 Functional Design 에서 속성을 식별하고 (PBT-01), 해당하는 PBT 를 작성한다
- Dart 와 Kotlin 모두 PBT 대상 코드가 있으므로 언어마다 프레임워크를 고른다 (PBT-09, NFR Requirements stage 에서 결정)
- PBT 는 예시 기반 테스트를 대체하지 않고 보완한다 (PBT-10)

### NFR-05: 유지보수성
- 새 fake · override 는 `test/helpers/` 의 기존 방식 (Riverpod override, fake 구현) 을 따른다 (CLAUDE.md)
- 코드 포맷은 줄 길이 120 (`dart format --line-length 120`)

## 복원력 결정 사항 (Resiliency Decisions, 확장 활성)

이 앱은 서버 · 클라우드 배포가 없는 개인용 Android 앱이다. 사용자 결정은 다음과 같다.

| 규칙 | 결정 | 출처 |
| --- | --- | --- |
| RESILIENCY-01 워크로드 분류 | 아래 표 참조 | AI 제안 (검토 대상) |
| RESILIENCY-02 RTO/RPO · DR 전략 | N/A: 리전 간 DR 불필요 | 후속 Q4=E |
| RESILIENCY-03 변경 관리 | N/A: 개인용 앱으로 정식 변경 관리 대상에서 제외. 근거: 사용자 1명, 배포 대상이 본인 기기뿐 | 후속 Q5=C |
| RESILIENCY-04 CI/CD | 기존 GitHub Actions 를 바탕으로 APK 빌드 · 산출물 업로드 단계 추가 (FR-09) | 2차 Q2=B |
| RESILIENCY-04 롤백 | `git revert` 후 다시 빌드 · 설치 | 2차 Q3=B |
| RESILIENCY-04 배포 방식 | Direct / in-place (APK 직접 설치) | 후속 Q8=A |
| RESILIENCY-08 리전 구성 | 단일 리전 멀티 존 선택. 실제로는 서버가 없어 존 · 리전 개념이 적용되지 않음 | 후속 Q9=A |
| RESILIENCY-15 장애 대응 | 가벼운 장애 대응 · 오류 교정 (COE) 프로세스를 AI-DLC 가 제안 (Operations 또는 NFR Design 에서 작성) | 후속 Q10=B |
| RESILIENCY-14 복원력 테스트 방식 | NFR Design 에서 질문 예정 | 규칙상 NFR Design |

### 워크로드 분류 (RESILIENCY-01)

| 구성 요소 | 중요도 | 사용 불가 시 영향 | 상류 · 하류 의존 |
| --- | --- | --- | --- |
| 폰 재생 경로 (`PhoneBackend` → `PlaybackCore` → TIDAL Player SDK) | High | 폰에서 음악 재생 불가 | 상류: `PlayerManager` / 하류: TIDAL API · CDN |
| DLNA 재생 경로 (`DlnaBackend`, `DlnaManager`, `TidalStreamProxyServer`) | High | 스피커 재생 불가 (앱의 핵심 차별 기능) | 상류: `PlayerManager` / 하류: DLNA 렌더러, TIDAL CDN |
| 미디어 세션 (`WaveAudioHandler`) | Medium | 잠금화면 · 블루투스 버튼 조작 불가, 앱 화면에서는 재생 가능 | 상류: audio_service / 하류: `PlayerManager`, `DlnaManager` |

매출 · 규제 영향은 없음 (개인용).

## 확장 설정 (Extension Configuration)

| Extension | Enabled | 비고 |
| --- | --- | --- |
| Security Baseline | No | 1차 Q6=B |
| Resiliency Baseline | Yes | 1차 Q7=A |
| Property-Based Testing | Yes (전체 강제) | 1차 Q8=A |

## 범위 밖 (Out of Scope)

- 새 기능 추가, UI 변경
- Flutter 3.47+ 대응 (`material.dart` 폐기 예정), release 서명, cleartext 허용 범위, `clientSecret` 처리 (Reverse Engineering 에서 찾은 다른 위험 항목)
- 실기기 · 실제 렌더러 확인 (`docs/dlna-compat.md` 갱신 없음)
- Kotlin 커버리지 도구 (JaCoCo) 도입

## 답변 반영 위치 (Answer Traceability)

| 질문 | 답 | 반영 위치 |
| --- | --- | --- |
| 1차 Q1 · Q2 | C, A | 의도 분석, FR-01 ~ FR-06 |
| 1차 Q3 | B | NFR-02 |
| 1차 Q4 | A | 의도 분석, 워크로드 분류 |
| 1차 Q5 | B | FR-07 |
| 1차 Q6 · Q7 · Q8 | B, A, A | 확장 설정, NFR-04 |
| 후속 Q1 | A | FR-01 ~ FR-06 |
| 후속 Q2 | B | FR-08 |
| 후속 Q3 + 2차 Q1 | B, A | NFR-01 |
| 후속 Q4 · Q5 · Q8 · Q9 · Q10 | E, C, A, A, B | 복원력 결정 사항 |
| 후속 Q6 + 2차 Q2 | B, B | FR-09, 복원력 결정 사항 |
| 후속 Q7 + 2차 Q3 | B, B | 복원력 결정 사항 (롤백) |

## 주요 요구사항 요약

- 테스트가 없는 6개 컴포넌트 (Dart 4, Kotlin 2) 의 공개 동작 · 이벤트 변환 · 오류 경로를 자동 테스트로 덮는다
- Dart 대상 4개 파일 각각 라인 커버리지 80% 이상, Kotlin 은 FR-05 · FR-06 동작 목록 기준
- 테스트에 필요한 최소 대체 지점만 운영 코드에 추가하고, 발견 버그는 실패 테스트 + 별도 커밋으로 수정
- CI 에 커버리지 검사와 debug APK 산출물 업로드 추가
- PBT 확장 전체 강제, 복원력 확장은 기기 앱 특성상 대부분 N/A 로 결정됨
