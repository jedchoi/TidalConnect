# 도메인 엔티티 (Domain Entities) - android-native-tests

이 unit 이 다루는 데이터와, 속성 기반 테스트의 생성기가 만들 값의 범위다. 새 타입은 Application Design (`component-methods.md`) 에서 정한 것뿐이다.

## 1. 새 타입 (router 분리로 생김)

| 타입 | 구성 | 쓰이는 곳 |
| --- | --- | --- |
| `CommandResult` | 세 가지 중 하나: `Success(value: Any?)`, `Error(code: String, message: String?)`, `NotImplemented` | router 의 반환값. `PlaybackCore` 가 채널 응답으로 옮긴다 |
| `PlayerControls` | 동작 8개: `playTrack(trackId)`, `pause()`, `resume()`, `seekTo(msec)`, `stop()`, `skipToNext()`, `setNextTrack(trackId)`, `setAudioQuality(name)` | `TidalPlayerManager` 가 구현 |
| `AuthControls` | `initialize(clientId, clientSecret): Boolean`, `updateUserCredentials(userId, accessToken, expiresInSeconds: Long)`, `clearUserCredentials()` | `PlaybackCore` 안에서 구현 |
| `DeviceControls` | `phoneVolumePercent(): Int`, `setPhoneVolumePercent(percent)`, `requestNotificationPermission(): Boolean`, `setWifiLock(enabled)` | `PlaybackCore` 안에서 구현 |
| `ProxyRegistrar` | `registerTrackStream(trackId, directUrl, manifestXml, allowedHost, mimeType): String?` (null = Wi-Fi 없음) | `PlaybackCore` 안에서 구현 |

## 2. 기존 엔티티

| 엔티티 | 필드 | 위치 |
| --- | --- | --- |
| `TidalStreamProxyServer.StreamInfo` | `trackId`, `directUrl` (기본 `""`), `manifestXml` (기본 `""`), `allowedHost` (기본 `""`, 빈 값이면 제한 없음), `mimeType` (기본 `audio/mp4`) | `TidalStreamProxyServer.kt` |
| 등록부 | 토큰 → `StreamInfo`. 삽입 순서를 지키며 최근 3개만 유지 | 같은 파일 |
| `DashManifest` | `initializationUrl?`, `mediaTemplate`, `startNumber`, `segmentCount`, `segmentUrl(index)` | `DashManifest.kt` (이 unit 에서 바꾸지 않음) |
| 재발급 응답 | 맵 `{directUrl, manifestXml, mimeType}` 또는 null | `streamRefresher` 의 반환값 |

### 채널 데이터

| 데이터 | 형태 | 기준 |
| --- | --- | --- |
| 채널 호출 | 메서드 이름 + 인자 맵 (`Map<String, Any?>`) | `business-rules.md` 1절의 메서드 표, `api-documentation.md` C절 |
| 성공 값 | 맵, 정수, 불리언, null 중 하나 | 같은 표 |

### 프록시 주소

```text
http://<바인딩 주소>:<포트>/audio/<토큰>.<확장자>
  바인딩 주소: 운영은 Wi-Fi IPv4 주소, 테스트는 127.0.0.1
  포트: 운영은 8765, 테스트는 임시 포트
  토큰: 16자의 16진수 소문자 (8바이트 난수)
  확장자: flac, m4a, mp3 중 하나
```

## 3. 엔티티 관계

```text
채널 호출 (method, args) --> PlaybackCommandRouter --> CommandResult
                                |-- AuthControls
                                |-- PlayerControls (없을 수 있음)
                                |-- DeviceControls
                                `-- ProxyRegistrar --> TidalStreamProxyServer.registerTrackStream --> 프록시 주소

프록시 주소의 토큰 --> 등록부 --> StreamInfo --> 직접 주소 (CDN) 또는 DashManifest (세그먼트 주소들)
재발급 응답 --> StreamInfo 갱신
```

## 4. 생성기 범위 (PBT 입력)

속성 기반 테스트의 생성기는 아래 범위의 값을 만든다 (PBT-07). 타입이 계약과 다른 인자는 범위 밖이다 (`business-rules.md` 관찰 사항 O-1).

| 생성기 | 만드는 값 | 쓰는 속성 |
| --- | --- | --- |
| 모르는 메서드 이름 | 16개 메서드 이름이 아닌 문자열: 빈 문자열, 임의의 영문자 문자열, 알려진 이름의 대소문자를 바꾼 것 · 앞뒤에 글자를 붙인 것 | P-CR-1 |
| 플레이어 동작 이름 | 플레이어 동작 8개 (또는 `stopTrack` 을 뺀 7개) 중 하나 | P-CR-2, P-CR-3 |
| 곡 ID | 숫자로 된 문자열 1 ~ 12자리, 그리고 빈 문자열 | P-CR-4, P-CR-5 |
| 재생 위치 | 0 ~ 36,000,000 밀리초의 정수 (Int 와 Long 두 타입으로) | P-CR-4 |
| 볼륨 | −1000 ~ 1000 의 정수 | P-CR-4 |
| 음질 이름 | `LOW`, `HIGH`, `LOSSLESS`, `HI_RES_LOSSLESS` + 임의의 대문자 문자열 | P-CR-4 |
| 자격 증명 | `userId` · `accessToken` 은 임의의 영숫자 문자열 (가짜 값), `expiresInSeconds` 는 1 ~ 86,400 (Int 와 Long 두 타입으로) | P-CR-4 |
| 등록 인자 | 다섯 문자열 각각 "있음 (임의의 문자열: URL 모양, XML 조각, MIME, IPv4)" 또는 "없음" | P-CR-5 |
| 예외 | 메시지가 있는 것 (임의의 문자열, 한글 포함) 과 없는 것, 클래스는 `IllegalStateException` · `IllegalArgumentException` · `RuntimeException` | P-CR-3 |
| 임의의 채널 호출 | 16개 메서드 중 하나 + 그 메서드의 인자 (각각 있거나 없음) | P-CR-6 |
| MIME 문자열 | `audio/flac`, `audio/mp4`, `audio/m4a`, `audio/aac`, `audio/mpeg`, `application/octet-stream`, 빈 문자열 + 이 낱말들을 섞은 임의의 문자열 (예: `audio/x-flac; codecs=mp4`) | P-PX-2 |
| 등록 횟수 | 0 ~ 10 | P-PX-1, P-PX-3 |
| 허용 주소 | 빈 문자열, `127.0.0.1`, 문서용 예약 대역의 IPv4 주소, `localhost`, 임의의 짧은 문자열 | P-PX-4 |
| Range 값 | `bytes=a-b` (0 ≤ a ≤ b < 1,000,000) 와 `bytes=a-` | P-PX-5 |
| 바이트 내용 | 길이 0 ~ 65,536 의 임의 바이트 열 (0 과 경계 길이가 나오게) | P-PX-6 |
| DASH 내용 | 초기화 세그먼트 있음/없음, 세그먼트 1 ~ 8개, 각 세그먼트는 길이 1 ~ 4,096 의 임의 바이트 열 | P-PX-6 |

테스트 데이터의 주소는 `127.0.0.1` (테스트 서버), 문서용 예약 대역 (`192.0.2.0/24` 등), `.test` 도메인만 쓴다. 실제 토큰 · 키 · 서명 주소를 넣지 않는다.

## 5. 요구 데이터와의 대조 (FD-2)

| 요구사항이 다루는 데이터 | 이 문서의 엔티티 |
| --- | --- |
| FR-06 의 채널 메서드 · 반환 맵 · 오류 | 채널 데이터, `CommandResult` |
| FR-05 의 토큰 · 확장자 · 프록시 주소 | 프록시 주소, 등록부, `StreamInfo` |
| FR-05 의 재발급 | 재발급 응답 |
| FR-07 의 대체 지점 | 협력 인터페이스 4개 |

요구사항에 없는 엔티티: `DashManifest`. DASH 중계 규칙 (PX-18, PX-34 ~ PX-38) 에 필요해 넣었다. 이 unit 에서 바꾸지 않는다.
