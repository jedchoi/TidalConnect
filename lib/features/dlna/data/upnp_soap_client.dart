import 'package:dio/dio.dart';

class UPnPSoapClient {
  final Dio _dio;

  UPnPSoapClient({Dio? dio}) : _dio = dio ?? Dio();

  static String buildSetAVTransportURIXml(String streamUrl, String title) {
    return '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
      <InstanceID>0</InstanceID>
      <CurrentURI>$streamUrl</CurrentURI>
      <CurrentURIMetaData></CurrentURIMetaData>
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
      final response = await _dio.post(
        controlUrl,
        data: xmlPayload,
        options: Options(
          headers: {
            'Content-Type': 'text/xml; charset="utf-8"',
            'SOAPACTION': '"$soapAction"',
          },
        ),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
