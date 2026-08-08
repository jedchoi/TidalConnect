import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import '../../../core/utils/app_logger.dart';
import '../domain/models/dlna_device.dart';

class SSDPDiscoveryService {
  static const String multicastAddress = '239.255.255.250';
  static const int multicastPort = 1900;
  final Dio _dio;

  SSDPDiscoveryService({Dio? dio}) : _dio = dio ?? Dio();

  Future<List<DlnaDevice>> discoverDevices({Duration timeout = const Duration(seconds: 4)}) async {
    final List<DlnaDevice> devices = [DlnaDevice.localSpeaker];
    final Set<String> seenUsns = {DlnaDevice.localSpeaker.udn};

    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.multicastHops = 4;
      socket.broadcastEnabled = true;

      AppLogger.log('SSDP_NET', 'UDP Multicast 소켓 바인딩 성공 (${socket.address.address}:${socket.port})', type: LogType.network);

      final targets = [
        'urn:schemas-upnp-org:device:MediaRenderer:1',
        'urn:schemas-upnp-org:service:AVTransport:1',
        'ssdp:all',
        'upnp:rootdevice',
      ];

      void sendMSearchBursts() {
        for (final target in targets) {
          final mSearch =
              'M-SEARCH * HTTP/1.1\r\n'
              'HOST: 239.255.255.250:1900\r\n'
              'MAN: "ssdp:discover"\r\n'
              'MX: 3\r\n'
              'ST: $target\r\n'
              '\r\n';
          socket?.send(utf8.encode(mSearch), InternetAddress(multicastAddress), multicastPort);
          socket?.send(utf8.encode(mSearch), InternetAddress('255.255.255.255'), multicastPort);
        }
      }

      AppLogger.log('SSDP_NET', 'M-SEARCH 패킷 전송 (Target: MediaRenderer, AVTransport, ssdp:all)', type: LogType.network);
      sendMSearchBursts();
      Timer(const Duration(milliseconds: 600), () => sendMSearchBursts());

      final completer = Completer<List<DlnaDevice>>();
      final timer = Timer(timeout, () {
        socket?.close();
        if (!completer.isCompleted) {
          AppLogger.log('SSDP_NET', 'SSDP 탐색 타임아웃 (${timeout.inSeconds}초 소요). 발견된 기기: ${devices.length}개', type: devices.length > 1 ? LogType.success : LogType.warning);
          completer.complete(devices);
        }
      });

      socket.listen((RawSocketEvent event) async {
        if (event == RawSocketEvent.read) {
          final datagram = socket?.receive();
          if (datagram != null) {
            final response = utf8.decode(datagram.data);
            final headers = _parseHeaders(response);
            final location = headers['LOCATION'] ?? headers['location'];
            final usn = headers['USN'] ?? headers['usn'] ?? location;

            AppLogger.log('SSDP_NET', 'UDP 응답 수신 [from ${datagram.address.address}:${datagram.port}] LOCATION: $location', type: LogType.info);

            if (location != null && usn != null && !seenUsns.contains(usn)) {
              seenUsns.add(usn);
              final device = await _fetchDeviceDescription(location, usn);
              if (device != null) {
                devices.add(device);
                AppLogger.log('SSDP_NET', 'DLNA 렌더러 추가 성공: "${device.friendlyName}" (${device.locationUrl})', type: LogType.success);
              }
            }
          }
        }
      });

      return await completer.future;
    } catch (e) {
      socket?.close();
      AppLogger.log('SSDP_NET', 'SSDP 소켓 오류 발생: $e', type: LogType.error);
      return devices;
    }
  }

  Map<String, String> _parseHeaders(String response) {
    final Map<String, String> headers = {};
    final lines = response.split('\r\n');
    for (final line in lines) {
      final index = line.indexOf(':');
      if (index > 0) {
        final key = line.substring(0, index).trim().toUpperCase();
        final value = line.substring(index + 1).trim();
        headers[key] = value;
      }
    }
    return headers;
  }

  Future<DlnaDevice?> _fetchDeviceDescription(String locationUrl, String usn) async {
    try {
      AppLogger.log('SSDP_NET', 'GET $locationUrl (XML 명세 수신 시도)', type: LogType.network);
      final response = await _dio.get(
        locationUrl,
        options: Options(responseType: ResponseType.plain),
      );
      final xmlStr = response.data.toString();

      final isMediaDevice = xmlStr.contains('MediaRenderer') ||
          xmlStr.contains('AVTransport') ||
          xmlStr.contains('RenderingControl');

      if (!isMediaDevice) {
        AppLogger.log('SSDP_NET', '필터링됨: $locationUrl (MediaRenderer/AVTransport 미지원 기기)', type: LogType.info);
        return null;
      }

      final friendlyName = _extractXmlValue(xmlStr, 'friendlyName') ?? 'DLNA Media Renderer';
      final baseUri = Uri.parse(locationUrl);

      final rawAvTransport = _extractServiceUrl(xmlStr, 'AVTransport');
      final rawRenderingControl = _extractServiceUrl(xmlStr, 'RenderingControl');

      final avTransportUrl = rawAvTransport != null ? baseUri.resolve(rawAvTransport).toString() : locationUrl;
      final renderingControlUrl = rawRenderingControl != null ? baseUri.resolve(rawRenderingControl).toString() : locationUrl;

      return DlnaDevice(
        udn: usn,
        friendlyName: friendlyName,
        locationUrl: locationUrl,
        avTransportControlUrl: avTransportUrl,
        renderingControlUrl: renderingControlUrl,
      );
    } catch (e) {
      AppLogger.log('SSDP_NET', 'XML 명세 수신 예외 [URL: $locationUrl]: $e', type: LogType.warning);
      final baseUri = Uri.parse(locationUrl);
      return DlnaDevice(
        udn: usn,
        friendlyName: 'DLNA Audio Renderer (${baseUri.host})',
        locationUrl: locationUrl,
        avTransportControlUrl: locationUrl,
        renderingControlUrl: locationUrl,
      );
    }
  }

  String? _extractXmlValue(String xml, String tagName) {
    final startTag = '<$tagName>';
    final endTag = '</$tagName>';
    final start = xml.indexOf(startTag);
    final end = xml.indexOf(endTag);
    if (start != -1 && end != -1) {
      return xml.substring(start + startTag.length, end).trim();
    }
    return null;
  }

  String? _extractServiceUrl(String xml, String serviceTypeSub) {
    if (xml.contains(serviceTypeSub)) {
      final controlStart = xml.indexOf('<controlURL>', xml.indexOf(serviceTypeSub));
      final controlEnd = xml.indexOf('</controlURL>', controlStart);
      if (controlStart != -1 && controlEnd != -1) {
        return xml.substring(controlStart + '<controlURL>'.length, controlEnd).trim();
      }
    }
    return null;
  }
}
