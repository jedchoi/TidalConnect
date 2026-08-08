class DlnaDevice {
  final String udn;
  final String friendlyName;
  final String locationUrl;
  final String avTransportControlUrl;
  final String renderingControlUrl;
  final bool isLocalSpeaker;

  DlnaDevice({
    required this.udn,
    required this.friendlyName,
    required this.locationUrl,
    required this.avTransportControlUrl,
    required this.renderingControlUrl,
    this.isLocalSpeaker = false,
  });

  static DlnaDevice get localSpeaker => DlnaDevice(
        udn: 'local_speaker',
        friendlyName: '스마트폰 내장 스피커',
        locationUrl: '',
        avTransportControlUrl: '',
        renderingControlUrl: '',
        isLocalSpeaker: true,
      );

  factory DlnaDevice.fromSsdpHeader({
    required String usn,
    required String location,
    String? friendlyName,
    String? avTransportUrl,
    String? renderingControlUrl,
  }) {
    return DlnaDevice(
      udn: usn,
      friendlyName: friendlyName ?? 'DLNA 스피커 ($usn)',
      locationUrl: location,
      avTransportControlUrl: avTransportUrl ?? '',
      renderingControlUrl: renderingControlUrl ?? '',
    );
  }
}
