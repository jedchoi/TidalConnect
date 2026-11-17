package com.example.tidal_connect_lite

/**
 * Flutter가 보낸 채널 명령을 협력 객체 호출로 옮기고 결과를 만든다.
 *
 * Android·Flutter 타입에 의존하지 않아 JVM 단위 테스트로 검증할 수 있다.
 * 상태를 갖지 않는다. 플레이어는 인증 초기화가 끝나야 생기므로 호출할 때마다 [player]로 조회한다.
 *
 * @param player 지금의 플레이어. 아직 없으면 null을 돌려준다.
 */
class PlaybackCommandRouter(
    private val auth: AuthControls,
    private val player: () -> PlayerControls?,
    private val device: DeviceControls,
    private val proxy: ProxyRegistrar,
) {
    /**
     * 채널 명령 하나를 처리한다.
     *
     * @param method 채널 메서드 이름
     * @param args 채널 인자. 없으면 빈 맵
     */
    fun handle(method: String, args: Map<String, Any?>): CommandResult {
        // 뼈대: 아직 어떤 메서드도 처리하지 않는다.
        return CommandResult.NotImplemented
    }
}
