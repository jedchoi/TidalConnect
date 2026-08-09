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
      // Local mobile speaker
      return true;
    }

    final targetControlUrl = device.avTransportControlUrl.isNotEmpty ? device.avTransportControlUrl : device.locationUrl;
    if (targetControlUrl.isEmpty) {
      AppLogger.log('DLNA_PLAY', '원격 스피커 controlUrl 없음: ${device.friendlyName}', type: LogType.warning);
      return false;
    }

    AppLogger.log('DLNA_PLAY', 'DLNA 스피커 전송 시작: "${device.friendlyName}" ➔ $streamUrl', type: LogType.network);
    try {
      final setUriOk = await _soapClient.setAVTransportURI(targetControlUrl, streamUrl, title);
      if (setUriOk) {
        final playOk = await _soapClient.play(targetControlUrl);
        AppLogger.log('DLNA_PLAY', 'DLNA 재생 명령 응답: $playOk', type: LogType.success);
        return playOk;
      }
    } catch (e) {
      AppLogger.log('DLNA_PLAY', 'DLNA 스피커 재생 전송 실패: $e', type: LogType.error);
    }
    return false;
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
