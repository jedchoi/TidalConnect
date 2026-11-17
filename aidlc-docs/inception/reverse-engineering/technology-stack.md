# 기술 스택 (Technology Stack)

## 프로그래밍 언어
- Dart - SDK 제약 `>=3.0.0 <4.0.0`(`pubspec.yaml`), 잠금 파일 요구 `>=3.11.0`(`pubspec.lock`) - 앱 로직과 UI (`lib/`, `test/`)
- Kotlin - Kotlin Android 플러그인 `2.1.0`(`android/settings.gradle.kts`), JVM target 17 - 네이티브 재생·프록시 (`android/app/src/main/kotlin/`)
- Java - 17 (source/target compatibility) - 자동 생성 `GeneratedPluginRegistrant.java`만 존재
- Bash - `tool/check.sh` 점검 스크립트
- XML - Android 매니페스트·리소스, UPnP SOAP/DIDL-Lite, DASH MPD

## 프레임워크
- Flutter - 3.41.7(CI 고정, `.github/workflows/check.yml`), 잠금 파일 요구 `>=3.41.0` - UI 프레임워크(저장소에 플랫폼 폴더는 `android/`만 있어 대상은 Android)
- Material(`package:flutter/material.dart`) - Flutter 내장 - UI 위젯과 다크 테마
- flutter_riverpod - 2.4.9 - DI와 상태 구독
- audio_service - 0.18.19 - 미디어 세션, 알림, 포그라운드 서비스
- TIDAL Player SDK (`com.tidal.sdk:player`) - 0.0.70 - 폰 재생
- TIDAL Auth SDK (`com.tidal.sdk:auth`) - 0.10.1 - SDK 자격 증명
- NanoHTTPD - 2.3.1 - 로컬 HTTP 프록시 서버

## 인프라
- GitHub Actions - 푸시(main)·PR마다 `tool/check.sh` 실행(ubuntu-latest, Temurin Java 17, subosito/flutter-action@v2)
- 클라우드·서버·컨테이너·IaC - 없음
- 외부 서비스 - TIDAL(auth.tidal.com, login.tidal.com, api.tidal.com, resources.tidal.com, CDN), LAN의 DLNA 렌더러

## 빌드 도구
- Flutter CLI / pub - 3.41.7 - 의존성, 빌드, 테스트, 분석, 포맷
- Gradle (Kotlin DSL) - 래퍼 미포함(버전 미확인) - Android 빌드
- Android Gradle Plugin - 8.11.1 - Android 앱 빌드
- dev.flutter.flutter-plugin-loader - 1.0.0 - Flutter 플러그인 로딩
- dart format - Flutter 동봉 - 줄 길이 120 포맷 검사
- flutter analyze + flutter_lints - 5.0.0 - 정적 분석(`--fatal-infos`)

## 테스트 도구
- flutter_test - Flutter SDK 동봉 - Dart 단위·위젯 테스트(`test/`, 약 95개 `test`/`testWidgets` 호출)
- JUnit - 4.13.2 - Kotlin 단위 테스트(`DashManifestTest.kt`, `:app:testDebugUnitTest`)
- 자체 fake/override - `test/helpers/fakes.dart`, `test/helpers/app_overrides.dart`
- 커버리지 도구 - 설정 없음
