import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:xml/xml.dart';
import '../../../core/utils/app_logger.dart';
import '../domain/models/dlna_device.dart';

class SSDPDiscoveryService {
  static const String multicastAddress = '239.255.255.250';
  static const int multicastPort = 1900;
  final Dio _dio;

  SSDPDiscoveryService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 3),
              receiveTimeout: const Duration(seconds: 3),
            ));

  /// SSDP로 렌더러를 찾는다. 기기를 찾는 즉시 [onDeviceFound]로 알리고,
  /// 응답 대기 시간이 끝나면 진행 중인 기기 설명 요청까지 기다린 뒤 전체 목록을 돌려준다.
  Future<List<DlnaDevice>> discoverDevices({
    Duration timeout = const Duration(seconds: 4),
    void Function(DlnaDevice device)? onDeviceFound,
  }) async {
    final List<DlnaDevice> devices = [DlnaDevice.localSpeaker];
    final Set<String> seenLocations = {};
    final Set<String> seenUdns = {DlnaDevice.localSpeaker.udn};

    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.multicastHops = 4;
      socket.broadcastEnabled = true;

      AppLogger.log('SSDP_NET', 'UDP Multicast 소켓 바인딩 성공 (${socket.address.address}:${socket.port})',
          type: LogType.network);

      final targets = [
        'urn:schemas-upnp-org:device:MediaRenderer:1',
        'urn:schemas-upnp-org:service:AVTransport:1',
        'ssdp:all',
        'upnp:rootdevice',
      ];

      void sendMSearchBursts() {
        for (final target in targets) {
          final mSearch = 'M-SEARCH * HTTP/1.1\r\n'
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
      final pending = <Future<void>>[];
      Timer(timeout, () async {
        socket?.close();
        // 응답은 받았지만 설명 XML을 아직 받는 중인 기기를 버리지 않는다(요청마다 3초 타임아웃).
        await Future.wait(pending);
        if (!completer.isCompleted) {
          AppLogger.log('SSDP_NET', 'SSDP 탐색 종료. 발견 기기: ${devices.length}개',
              type: devices.length > 1 ? LogType.success : LogType.warning);
          completer.complete(devices);
        }
      });

      socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket?.receive();
          if (datagram != null) {
            final response = utf8.decode(datagram.data);
            final headers = _parseHeaders(response);
            final location = headers['LOCATION'] ?? headers['location'];
            final rawUsn = headers['USN'] ?? headers['usn'] ?? location;

            if (location == null) return;

            // Extract base UUID / UDN (strip subservice suffix like ::urn:schemas-upnp-org:...)
            final baseUdn = (rawUsn ?? location).split('::').first.trim();

            // Strict Deduplication Check before HTTP fetch
            if (seenLocations.contains(location) || seenUdns.contains(baseUdn)) {
              return;
            }

            seenLocations.add(location);
            seenUdns.add(baseUdn);

            AppLogger.log('SSDP_NET', 'UDP 중복 없음 확인 ➔ XML 수신 시작 [from ${datagram.address.address}] LOCATION: $location',
                type: LogType.info);

            pending.add(_fetchDeviceDescription(location, baseUdn).then((device) {
              if (device == null || completer.isCompleted) return;
              // 같은 기기가 여러 인터페이스로 응답한 경우만 걸러낸다(이름이 같은 다른 스피커는 유지).
              final isDuplicate =
                  devices.any((d) => d.locationUrl == device.locationUrl || (d.udn.isNotEmpty && d.udn == device.udn));
              if (isDuplicate) return;
              devices.add(device);
              onDeviceFound?.call(device);
              AppLogger.log('SSDP_NET', 'DLNA 렌더러 등록: "${device.friendlyName}"', type: LogType.success);
            }));
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
      AppLogger.log('SSDP_NET', 'GET $locationUrl (XML 명세 수신)', type: LogType.network);
      final response = await _dio.get(
        locationUrl,
        options: Options(responseType: ResponseType.plain),
      );
      final device = parseDeviceDescription(response.data.toString(), locationUrl: locationUrl, fallbackUdn: usn);
      if (device == null) {
        AppLogger.log('SSDP_NET', '필터링됨 (AVTransport 미지원): $locationUrl', type: LogType.info);
      }
      return device;
    } catch (e) {
      // 설명을 받지 못한 기기는 렌더러인지 알 수 없으므로 목록에 넣지 않는다.
      AppLogger.log('SSDP_NET', 'XML 명세 수신 실패 [$locationUrl]: $e', type: LogType.warning);
      return null;
    }
  }

  /// UPnP 기기 설명 XML을 해석한다. AVTransport 서비스가 있는 기기(루트 또는 내장 기기)만 렌더러로 본다.
  static DlnaDevice? parseDeviceDescription(String xml, {required String locationUrl, String fallbackUdn = ''}) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xml);
    } catch (_) {
      return null;
    }

    final urlBase = _childText(doc.rootElement, 'URLBase');
    final base = Uri.parse(urlBase.isNotEmpty ? urlBase : locationUrl);

    for (final device in _elements(doc, 'device')) {
      final services = _directChild(device, 'serviceList')?.childElements.where((e) => e.name.local == 'service') ??
          const <XmlElement>[];
      String? controlUrlFor(String type) {
        for (final service in services) {
          if (_childText(service, 'serviceType').contains(type)) {
            final url = _childText(service, 'controlURL');
            if (url.isNotEmpty) return base.resolve(url).toString();
          }
        }
        return null;
      }

      final avTransport = controlUrlFor('AVTransport');
      if (avTransport == null) continue;
      final udn = _childText(device, 'UDN');
      final name = _childText(device, 'friendlyName');
      return DlnaDevice(
        udn: udn.isNotEmpty ? udn : fallbackUdn,
        friendlyName: name.isNotEmpty ? name : 'DLNA Media Renderer (${base.host})',
        locationUrl: locationUrl,
        avTransportControlUrl: avTransport,
        renderingControlUrl: controlUrlFor('RenderingControl') ?? '',
      );
    }
    return null;
  }

  static Iterable<XmlElement> _elements(XmlNode node, String localName) =>
      node.descendants.whereType<XmlElement>().where((e) => e.name.local == localName);

  static XmlElement? _directChild(XmlElement element, String localName) {
    for (final child in element.childElements) {
      if (child.name.local == localName) return child;
    }
    return null;
  }

  static String _childText(XmlElement element, String localName) =>
      _directChild(element, localName)?.innerText.trim() ?? '';
}
