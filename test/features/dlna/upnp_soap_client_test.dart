import 'package:flutter_test/flutter_test.dart';
import 'package:tidal_connect_lite/features/dlna/data/upnp_soap_client.dart';
import 'package:tidal_connect_lite/features/dlna/domain/models/dlna_device.dart';

void main() {
  test('generateSetAVTransportURIXml should produce valid SOAP envelope', () {
    final xml = UPnPSoapClient.buildSetAVTransportURIXml(
      'https://stream.tidal.com/audio.flac',
      'Test Song',
    );
    expect(xml, contains('<CurrentURI>https://stream.tidal.com/audio.flac</CurrentURI>'));
    expect(xml, contains('u:SetAVTransportURI'));
  });

  test('generateSetVolumeXml should produce valid RenderingControl SOAP payload', () {
    final xml = UPnPSoapClient.buildSetVolumeXml(75);
    expect(xml, contains('<DesiredVolume>75</DesiredVolume>'));
    expect(xml, contains('u:SetVolume'));
  });

  test('DlnaDevice localSpeaker fallback properties', () {
    final local = DlnaDevice.localSpeaker;
    expect(local.isLocalSpeaker, true);
    expect(local.friendlyName, contains('스마트폰 내장 스피커'));
  });
}
