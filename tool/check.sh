#!/usr/bin/env bash
# 커밋 전 로컬 점검: 포맷 → 정적 분석 → Dart 테스트 → Kotlin 단위 테스트.
# 사용법: tool/check.sh [--skip-android]
set -euo pipefail
cd "$(dirname "$0")/.."

step() { printf '\n\033[1;36m▶ %s\033[0m\n' "$1"; }

step "flutter pub get"
flutter pub get

step "dart format (변경 사항 검사)"
dart format --output=none --set-exit-if-changed --line-length 120 lib test

step "flutter analyze"
flutter analyze --fatal-infos

step "flutter test"
# CI에서도 로컬과 같은 형식(실패 시 [E] 표시)으로 출력해 로그를 읽기 쉽게 한다.
flutter test --reporter expanded

if [[ "${1:-}" != "--skip-android" ]]; then
  step "Kotlin 단위 테스트 (android:testDebugUnitTest)"
  (cd android && ./gradlew --quiet :app:testDebugUnitTest)
fi

printf '\n\033[1;32m모든 점검 통과\033[0m\n'
