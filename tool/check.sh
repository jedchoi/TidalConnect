#!/usr/bin/env bash
# 커밋 전 로컬 점검: 포맷 → 정적 분석 → Dart 테스트(커버리지 수집) → 커버리지 검사 → Kotlin 단위 테스트.
# 사용법: tool/check.sh [--skip-android]
#   --skip-android  Kotlin 단위 테스트만 건너뛴다. 커버리지 검사는 실행한다.
# Kotlin 단계는 JDK 17이 필요하다. JAVA_HOME이 없고 java도 실행되지 않으면 macOS에서 스스로 찾는다.
set -euo pipefail
cd "$(dirname "$0")/.."

step() { printf '\n\033[1;36m▶ %s\033[0m\n' "$1"; }

step "flutter pub get"
flutter pub get

step "dart format (변경 사항 검사)"
dart format --output=none --set-exit-if-changed --line-length 120 lib test tool

step "flutter analyze"
flutter analyze --fatal-infos

step "flutter test"
# CI에서도 로컬과 같은 형식(실패 시 [E] 표시)으로 출력해 로그를 읽기 쉽게 한다.
# 커버리지(coverage/lcov.info)를 함께 모은다. 테스트는 한 번만 실행한다.
flutter test --coverage --reporter expanded

step "커버리지 검사 (대상 파일별 기준은 tool/coverage_gate.dart)"
# `dart run`은 표 앞에 진행 표시를 줄바꿈 없이 내므로 파일을 직접 실행한다.
dart tool/coverage_gate.dart

# JAVA_HOME이 없고 java도 실행되지 않을 때만 JDK 17을 찾아 이 실행 안에서 JAVA_HOME을 지정한다.
# macOS의 /usr/bin/java는 JDK가 없어도 있는 대역이라 `command -v`가 아니라 실제로 실행해 본다.
find_jdk() {
  if [[ -n "${JAVA_HOME:-}" ]] || java -version >/dev/null 2>&1; then
    return 0
  fi
  local candidate
  if [[ -x /usr/libexec/java_home ]] && candidate="$(/usr/libexec/java_home -v 17 2>/dev/null)"; then
    export JAVA_HOME="$candidate"
  elif [[ -x /opt/homebrew/opt/openjdk@17/bin/java ]]; then
    export JAVA_HOME=/opt/homebrew/opt/openjdk@17
  else
    echo "JDK 17을 찾지 못했습니다. JAVA_HOME을 지정하거나 \`brew install openjdk@17\`로 설치하세요." >&2
    return 1
  fi
  echo "JAVA_HOME이 없어 찾은 JDK를 씁니다: $JAVA_HOME"
}

if [[ "${1:-}" != "--skip-android" ]]; then
  step "Kotlin 단위 테스트 (android:testDebugUnitTest)"
  find_jdk
  (cd android && ./gradlew --quiet :app:testDebugUnitTest)
fi

printf '\n\033[1;32m모든 점검 통과\033[0m\n'
