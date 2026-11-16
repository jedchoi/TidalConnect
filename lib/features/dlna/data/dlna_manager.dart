import 'package:flutter/foundation.dart';
import '../../../core/utils/app_logger.dart';
import '../domain/models/dlna_device.dart';
import 'ssdp_discovery_service.dart';
import 'upnp_soap_client.dart';

class DlnaManager {
  static final DlnaManager instance = DlnaManager._internal();
  DlnaManager._internal();

  final ValueNotifier<List<DlnaDevice>> devicesNotifier = ValueNotifier([DlnaDevice.localSpeaker]);
  final ValueNotifier<DlnaDevice> selectedDeviceNotifier = ValueNotifier(DlnaDevice.localSpeaker);
  final ValueNotifier<bool> isSearchingNotifier = ValueNotifier(false);

  final SSDPDiscoveryService _ssdpService = SSDPDiscoveryService();
  final UPnPSoapClient _soapClient = UPnPSoapClient();

  List<DlnaDevice> get devices => devicesNotifier.value;
  DlnaDevice get selectedDevice => selectedDeviceNotifier.value;

  void selectDevice(DlnaDevice device) {
    selectedDeviceNotifier.value = device;
    AppLogger.log('DLNA_UI', '오디오 출력 기기 변경: "${device.friendlyName}" (${device.locationUrl})', type: LogType.success);
  }

  Future<bool> playOnSelectedDevice({required String streamUrl, required String title}) async {
    final device = selectedDevice;
    if (device.isLocalSpeaker) {
      // Local mobile speaker handled natively via TIDAL SDK Player
      return true;
    }

    final targetControlUrl = device.avTransportControlUrl.isNotEmpty ? device.avTransportControlUrl : device.locationUrl;
    if (targetControlUrl.isEmpty) {
      AppLogger.log('DLNA_PLAY', '원격 스피커 controlUrl 없음: ${device.friendlyName}', type: LogType.warning);
      return false;
    }

    AppLogger.log('DLNA_PLAY', 'DLNA 스피커 전송 시작: "${device.friendlyName}" ➔ ${maskUrl(streamUrl)}', type: LogType.network);
    try {
      // ① Stop 먼저: PAUSED 상태의 DLNA 렌더러는 SetAVTransportURI를 무시하는 경우가 있음
      //   Stop → STOPPED 상태로 전환 후 새 URI 설정
      await _soapClient.stop(targetControlUrl);
      AppLogger.log('DLNA_PLAY', 'DLNA Stop 전송 완료 (SetAVTransportURI 전 초기화)', type: LogType.info);

      // ② SetAVTransportURI: 새 스트림 URL 등록
      final setUriOk = await _soapClient.setAVTransportURI(targetControlUrl, streamUrl, title);
      AppLogger.log('DLNA_PLAY', 'SetAVTransportURI 결과: $setUriOk', type: LogType.info);

      if (setUriOk) {
        // ③ Play: 재생 시작
        final playOk = await _soapClient.play(targetControlUrl);
        AppLogger.log('DLNA_PLAY', 'DLNA Play 명령 응답: $playOk', type: LogType.success);
        return playOk;
      }
    } catch (e) {
      AppLogger.log('DLNA_PLAY', 'DLNA 스피커 재생 전송 실패: $e', type: LogType.error);
    }
    return false;
  }

  Future<bool> pauseCurrent() async {
    final device = selectedDevice;
    if (device.isLocalSpeaker) return true;
    final targetControlUrl = device.avTransportControlUrl.isNotEmpty ? device.avTransportControlUrl : device.locationUrl;
    if (targetControlUrl.isEmpty) return false;
    return await _soapClient.pause(targetControlUrl);
  }

  Future<bool> resumeCurrent() async {
    final device = selectedDevice;
    if (device.isLocalSpeaker) return true;
    final targetControlUrl = device.avTransportControlUrl.isNotEmpty ? device.avTransportControlUrl : device.locationUrl;
    if (targetControlUrl.isEmpty) return false;
    return await _soapClient.play(targetControlUrl);
  }

  Future<bool> seek(int seconds) async {
    final device = selectedDevice;
    if (device.isLocalSpeaker) return true;
    final targetControlUrl = device.avTransportControlUrl.isNotEmpty ? device.avTransportControlUrl : device.locationUrl;
    if (targetControlUrl.isEmpty) return false;

    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    final relTime = '$h:$m:$s';

    AppLogger.log('DLNA_PLAY', '스피커 탐색(Seek) 요청 -> $relTime', type: LogType.info);
    return await _soapClient.seek(targetControlUrl, relTime);
  }

  /// 선택된 스피커의 현재 볼륨(0~100)을 읽는다. 읽지 못하면 null.
  Future<int?> fetchVolume() async {
    final device = selectedDevice;
    if (device.isLocalSpeaker) return null;
    final targetRenderingUrl = device.renderingControlUrl.isNotEmpty ? device.renderingControlUrl : device.locationUrl;
    if (targetRenderingUrl.isEmpty) return null;
    final volume = await _soapClient.getVolume(targetRenderingUrl);
    return volume?.clamp(0, 100);
  }

  Future<bool> setVolume(int volumePercent) async {
    final clamped = volumePercent.clamp(0, 100);

    final device = selectedDevice;
    if (device.isLocalSpeaker) return true;

    final targetRenderingUrl = device.renderingControlUrl.isNotEmpty ? device.renderingControlUrl : device.locationUrl;
    if (targetRenderingUrl.isEmpty) return false;

    AppLogger.log('DLNA_VOL', '🔊 스피커 볼륨 설정 요청: $clamped% -> $targetRenderingUrl', type: LogType.info);
    return await _soapClient.setVolume(targetRenderingUrl, clamped);
  }

  /// 스피커의 실제 재생 위치(초)와 전체 길이(초)를 가져옵니다.
  Future<Map<String, int>?> syncPosition() async {
    final device = selectedDevice;
    if (device.isLocalSpeaker) return null;

    final targetControlUrl = device.avTransportControlUrl.isNotEmpty ? device.avTransportControlUrl : device.locationUrl;
    if (targetControlUrl.isEmpty) return null;

    final info = await _soapClient.getPositionInfo(targetControlUrl);
    if (info != null) {
      final relSec = _parseDurationToSeconds(info['RelTime'] ?? '');
      final durSec = _parseDurationToSeconds(info['TrackDuration'] ?? '');
      return {'progress': relSec, 'duration': durSec};
    }
    return null;
  }

  int _parseDurationToSeconds(String timeStr) {
    if (timeStr.isEmpty || timeStr == 'NOT_IMPLEMENTED') return 0;
    final parts = timeStr.split(':');
    if (parts.length == 3) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      final s = double.tryParse(parts[2])?.toInt() ?? 0;
      return h * 3600 + m * 60 + s;
    }
    return 0;
  }

  Future<bool> stopCurrent() async {
    final device = selectedDevice;
    if (device.isLocalSpeaker) return true;
    final targetControlUrl = device.avTransportControlUrl.isNotEmpty ? device.avTransportControlUrl : device.locationUrl;
    if (targetControlUrl.isEmpty) return false;
    return await _soapClient.stop(targetControlUrl);
  }

  Future<List<DlnaDevice>> discoverDevices() async {
    if (isSearchingNotifier.value) return devices;
    isSearchingNotifier.value = true;
    AppLogger.log('DLNA_UI', '전역 DLNA 네트워크 탐색 시작...', type: LogType.info);

    try {
      final newDevices = await _ssdpService.discoverDevices();
      devicesNotifier.value = List.unmodifiable(newDevices);
      
      final remoteCount = newDevices.where((d) => !d.isLocalSpeaker).length;
      AppLogger.log('DLNA_UI', '전역 DLNA 탐색 완료. 총 ${newDevices.length}개 기기 (원격 스피커: $remoteCount개)', type: LogType.success);
      return newDevices;
    } catch (e) {
      AppLogger.log('DLNA_UI', '전역 DLNA 탐색 중 예외 발생: $e', type: LogType.error);
      return devices;
    } finally {
      isSearchingNotifier.value = false;
    }
  }
}
