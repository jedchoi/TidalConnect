package com.example.tidal_connect_lite

import io.kotest.property.PropTestConfig
import kotlinx.coroutines.runBlocking

/**
 * 속성 기반 테스트의 공통 설정.
 *
 * seed는 고정값을 써서 로컬과 CI가 매번 같은 입력으로 실행한다. Dart 쪽(`test/helpers/pbt_config.dart`)과 같은 값이다.
 * - 실패를 재현할 때: 출력된 seed로 `PBT_SEED=<seed> ./gradlew :app:testDebugUnitTest --tests "<테스트>"`
 * - 다른 입력을 탐색할 때: `PBT_SEED=$RANDOM ./gradlew :app:testDebugUnitTest --rerun-tasks`
 */
const val DEFAULT_PBT_SEED = 20261117L

/** 환경 변수 `PBT_SEED`가 정수면 그 값, 아니면 [DEFAULT_PBT_SEED]. */
fun pbtSeed(): Long = System.getenv("PBT_SEED")?.toLongOrNull() ?: DEFAULT_PBT_SEED

/**
 * 속성 하나의 설정. 실행 횟수를 항상 명시한다(프레임워크 기본값은 1000회다).
 * 소켓을 쓰지 않는 속성은 100회, 실제 HTTP 요청을 보내는 속성은 그보다 적게 둔다.
 */
fun pbt(iterations: Int = 100): PropTestConfig = PropTestConfig(seed = pbtSeed(), iterations = iterations)

/** `checkAll`은 suspend 함수라 JUnit 4 테스트 메서드에서는 이 함수로 감싸 실행한다. */
fun property(block: suspend () -> Unit) = runBlocking { block() }
