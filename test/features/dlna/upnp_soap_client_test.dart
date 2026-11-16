import 'package:flutter_test/flutter_test.dart';
import 'package:tidal_connect_lite/features/dlna/data/upnp_soap_client.dart';
import 'package:tidal_connect_lite/features/dlna/domain/models/dlna_device.dart';

void main() {
  test('generateSetAVTransportURIXml should produce valid SOAP envelope', () {
    final xml = UPnPSoapClient.buildSetAVTransportURIXml(
      'http://192.168.0.10:8765/audio/abc.flac',
      const DidlMetadata(
        title: 'Test & Song',
        artist: 'Artist',
        album: 'Album',
        albumArtUri: 'https://resources.tidal.com/images/a/b/640x640.jpg',
        durationSeconds: 215,
        mimeType: 'audio/flac',
      ),
    );
    expect(xml, contains('<CurrentURI>http://192.168.0.10:8765/audio/abc.flac</CurrentURI>'));
    expect(xml, contains('u:SetAVTransportURI'));
    // 메타데이터는 한 번 더 이스케이프되어 들어간다.
    expect(xml, contains('Test &amp;amp; Song'));
    expect(xml, contains('upnp:artist'));
    expect(xml, contains('upnp:albumArtURI'));
    expect(xml, contains('http-get:*:audio/flac:*'));
    expect(xml, contains('duration=&quot;0:03:35.000&quot;'));
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
