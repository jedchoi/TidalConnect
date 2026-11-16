import 'package:dio/dio.dart';
import '../../../core/utils/app_logger.dart';

class UPnPSoapClient {
  final Dio _dio;

  UPnPSoapClient({Dio? dio}) : _dio = dio ?? Dio();

  static String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static String buildSetAVTransportURIXml(String streamUrl, String title) {
    final escapedStreamUrl = _escapeXml(streamUrl);
    final escapedTitle = _escapeXml(title.isNotEmpty ? title : 'Tidal Music');

    final didlLite = '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
        '<item id="0" parentID="0" restricted="1">'
        '<dc:title>$escapedTitle</dc:title>'
        '<upnp:class>object.item.audioItem.musicTrack</upnp:class>'
        '<res protocolInfo="http-get:*:*:*">$escapedStreamUrl</res>'
        '</item>'
        '</DIDL-Lite>';

    final escapedMetaData = _escapeXml(didlLite);

    return '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
      <InstanceID>0</InstanceID>
      <CurrentURI>$escapedStreamUrl</CurrentURI>
      <CurrentURIMetaData>$escapedMetaData</CurrentURIMetaData>
    </u:SetAVTransportURI>
  </s:Body>
</s:Envelope>''';
  }

  static String buildPlayXml() {
    return '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
      <InstanceID>0</InstanceID>
      <Speed>1</Speed>
    </u:Play>
  </s:Body>
</s:Envelope>''';
  }

  static String buildPauseXml() {
    return '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:Pause xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
      <InstanceID>0</InstanceID>
    </u:Pause>
  </s:Body>
</s:Envelope>''';
  }

  static String buildStopXml() {
    return '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:Stop xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
      <InstanceID>0</InstanceID>
    </u:Stop>
  </s:Body>
</s:Envelope>''';
  }

  static String buildSeekXml(String relTime) {
    return '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:Seek xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
      <InstanceID>0</InstanceID>
      <Unit>REL_TIME</Unit>
      <Target>$relTime</Target>
    </u:Seek>
  </s:Body>
</s:Envelope>''';
  }

  static String buildSetVolumeXml(int volumePercent) {
    return '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:SetVolume xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
      <InstanceID>0</InstanceID>
      <Channel>Master</Channel>
      <DesiredVolume>$volumePercent</DesiredVolume>
    </u:SetVolume>
  </s:Body>
</s:Envelope>''';
  }

  Future<bool> setAVTransportURI(String controlUrl, String streamUrl, String title) async {
    return await _sendSoapRequest(
      controlUrl: controlUrl,
      soapAction: 'urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI',
      xmlPayload: buildSetAVTransportURIXml(streamUrl, title),
    );
  }

  Future<bool> play(String controlUrl) async {
    return await _sendSoapRequest(
      controlUrl: controlUrl,
      soapAction: 'urn:schemas-upnp-org:service:AVTransport:1#Play',
      xmlPayload: buildPlayXml(),
    );
  }

  Future<bool> pause(String controlUrl) async {
    return await _sendSoapRequest(
      controlUrl: controlUrl,
      soapAction: 'urn:schemas-upnp-org:service:AVTransport:1#Pause',
      xmlPayload: buildPauseXml(),
    );
  }

  Future<bool> stop(String controlUrl) async {
    return await _sendSoapRequest(
      controlUrl: controlUrl,
      soapAction: 'urn:schemas-upnp-org:service:AVTransport:1#Stop',
      xmlPayload: buildStopXml(),
    );
  }

  Future<bool> seek(String controlUrl, String relTime) async {
    return await _sendSoapRequest(
      controlUrl: controlUrl,
      soapAction: 'urn:schemas-upnp-org:service:AVTransport:1#Seek',
      xmlPayload: buildSeekXml(relTime),
    );
  }

  static String buildGetPositionInfoXml() {
    return '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:GetPositionInfo xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
      <InstanceID>0</InstanceID>
    </u:GetPositionInfo>
  </s:Body>
</s:Envelope>''';
  }

  static String buildGetVolumeXml() {
    return '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:GetVolume xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
      <InstanceID>0</InstanceID>
      <Channel>Master</Channel>
    </u:GetVolume>
  </s:Body>
</s:Envelope>''';
  }

  Future<Map<String, String>?> getPositionInfo(String controlUrl) async {
    try {
      final response = await _dio.post(
        controlUrl,
        data: buildGetPositionInfoXml(),
        options: Options(
          headers: {
            'Content-Type': 'text/xml; charset="utf-8"',
            'SOAPACTION': '"urn:schemas-upnp-org:service:AVTransport:1#GetPositionInfo"',
          },
          sendTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
        ),
      );
      if (response.statusCode == 200) {
        final xml = response.data.toString();
        final relTime = _extractXmlTag(xml, 'RelTime') ?? '00:00:00';
        final trackDuration = _extractXmlTag(xml, 'TrackDuration') ?? '00:00:00';
        return {'RelTime': relTime, 'TrackDuration': trackDuration};
      }
    } catch (_) {}
    return null;
  }

  Future<int?> getVolume(String controlUrl) async {
    try {
      final response = await _dio.post(
        controlUrl,
        data: buildGetVolumeXml(),
        options: Options(
          headers: {
            'Content-Type': 'text/xml; charset="utf-8"',
            'SOAPACTION': '"urn:schemas-upnp-org:service:RenderingControl:1#GetVolume"',
          },
          sendTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
        ),
      );
      if (response.statusCode == 200) {
        final xml = response.data.toString();
        final volStr = _extractXmlTag(xml, 'CurrentVolume');
        return volStr != null ? int.tryParse(volStr) : null;
      }
    } catch (_) {}
    return null;
  }

  static String? _extractXmlTag(String xml, String tag) {
    final start = xml.indexOf('<$tag>');
    final end = xml.indexOf('</$tag>');
    if (start != -1 && end != -1) {
      return xml.substring(start + tag.length + 2, end).trim();
    }
    return null;
  }

  Future<bool> setVolume(String controlUrl, int volumePercent) async {
    return await _sendSoapRequest(
      controlUrl: controlUrl,
      soapAction: 'urn:schemas-upnp-org:service:RenderingControl:1#SetVolume',
      xmlPayload: buildSetVolumeXml(volumePercent),
    );
  }

  Future<bool> _sendSoapRequest({
    required String controlUrl,
    required String soapAction,
    required String xmlPayload,
  }) async {
    try {
      AppLogger.log('UPNP_SOAP', 'POST $controlUrl [SOAPACTION: $soapAction]', type: LogType.network);
      final response = await _dio.post(
        controlUrl,
        data: xmlPayload,
        options: Options(
          headers: {
            'Content-Type': 'text/xml; charset="utf-8"',
            'SOAPACTION': '"$soapAction"',
          },
          sendTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
        ),
      );
      final isOk = response.statusCode == 200;
      AppLogger.log('UPNP_SOAP', 'SOAP 응답 코드 [HTTP ${response.statusCode}]: $isOk', type: isOk ? LogType.success : LogType.warning);
      return isOk;
    } catch (e) {
      AppLogger.log('UPNP_SOAP', 'SOAP 요청 실패 [URL: $controlUrl, Action: $soapAction]: $e', type: LogType.error);
      return false;
    }
  }
}
