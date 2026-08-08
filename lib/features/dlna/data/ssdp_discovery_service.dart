import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import '../domain/models/dlna_device.dart';

class SSDPDiscoveryService {
  static const String multicastAddress = '239.255.255.250';
  static const int multicastPort = 1900;
  final Dio _dio;

  SSDPDiscoveryService({Dio? dio}) : _dio = dio ?? Dio();

  Future<List<DlnaDevice>> discoverDevices({Duration timeout = const Duration(seconds: 3)}) async {
    final List<DlnaDevice> devices = [DlnaDevice.localSpeaker];
    final Set<String> seenUsns = {DlnaDevice.localSpeaker.udn};

    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.multicastHops = 2;
      socket.broadcastEnabled = true;

      const mSearch =
          'M-SEARCH * HTTP/1.1\r\n'
          'HOST: 239.255.255.250:1900\r\n'
          'MAN: "ssdp:discover"\r\n'
          'MX: 2\r\n'
          'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n'
          '\r\n';

      socket.send(utf8.encode(mSearch), InternetAddress(multicastAddress), multicastPort);

      final completer = Completer<List<DlnaDevice>>();
      final timer = Timer(timeout, () {
        socket?.close();
        if (!completer.isCompleted) {
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

            if (location != null && usn != null && !seenUsns.contains(usn)) {
              seenUsns.add(usn);
              final device = await _fetchDeviceDescription(location, usn);
              if (device != null) {
                devices.add(device);
              }
            }
          }
        }
      });

      return await completer.future;
    } catch (_) {
      socket?.close();
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
      final response = await _dio.get(locationUrl);
      final xmlStr = response.data.toString();
      final friendlyName = _extractXmlValue(xmlStr, 'friendlyName') ?? 'Chord Poly DLNA';
      final avTransportUrl = _extractServiceUrl(xmlStr, 'AVTransport') ?? locationUrl;
      final renderingControlUrl = _extractServiceUrl(xmlStr, 'RenderingControl') ?? locationUrl;

      return DlnaDevice(
        udn: usn,
        friendlyName: friendlyName,
        locationUrl: locationUrl,
        avTransportControlUrl: avTransportUrl,
        renderingControlUrl: renderingControlUrl,
      );
    } catch (_) {
      return DlnaDevice(
        udn: usn,
        friendlyName: 'Chord Poly (DLNA)',
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
