import 'package:flutter_test/flutter_test.dart';
import 'package:tidal_connect_lite/features/dlna/data/ssdp_discovery_service.dart';

const _renderer = '''<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <device>
    <deviceType>urn:schemas-upnp-org:device:MediaServer:1</deviceType>
    <friendlyName>Media Server</friendlyName>
    <UDN>uuid:server</UDN>
    <deviceList>
      <device>
        <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
        <friendlyName>Living Room</friendlyName>
        <UDN>uuid:renderer-1</UDN>
        <serviceList>
          <service>
            <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
            <controlURL>/rc/control</controlURL>
          </service>
          <service>
            <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
            <controlURL>avt/control</controlURL>
          </service>
        </serviceList>
      </device>
    </deviceList>
  </device>
</root>''';

void main() {
  test('finds the embedded renderer and resolves control URLs', () {
    final device = SSDPDiscoveryService.parseDeviceDescription(
      _renderer,
      locationUrl: 'http://192.168.0.20:49152/desc.xml',
    )!;
    expect(device.udn, 'uuid:renderer-1');
    expect(device.friendlyName, 'Living Room');
    expect(device.avTransportControlUrl, 'http://192.168.0.20:49152/avt/control');
    expect(device.renderingControlUrl, 'http://192.168.0.20:49152/rc/control');
  });

  test('ignores devices without AVTransport', () {
    const server = '<root><device><friendlyName>NAS</friendlyName><UDN>uuid:nas</UDN></device></root>';
    expect(SSDPDiscoveryService.parseDeviceDescription(server, locationUrl: 'http://10.0.0.2/d.xml'), isNull);
  });

  test('returns null for malformed XML', () {
    expect(SSDPDiscoveryService.parseDeviceDescription('<root><device>', locationUrl: 'http://x/d.xml'), isNull);
  });
}
