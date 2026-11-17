import 'dart:async';
import 'dart:collection';

import 'package:tidal_connect_lite/features/dlna/data/upnp_soap_client.dart';

/// 네트워크 없이 SOAP 액션을 기록하고 정해 둔 결과를 돌려주는 [UPnPSoapClient].
///
/// 액션 이름은 UPnP 액션 이름 그대로다:
/// `SetAVTransportURI`, `SetNextAVTransportURI`, `Play`, `Pause`, `Stop`, `Seek`,
/// `GetTransportInfo`, `GetPositionInfo`, `GetVolume`, `SetVolume`.
class FakeSoapClient extends UPnPSoapClient {
  /// 받은 액션(순서대로). 형식: `<액션>:<controlUrl>`.
  final List<String> calls = [];

  /// 명령 액션별 성공 여부. 지정하지 않으면 true.
  final Map<String, bool> commandResults = {};

  /// 여기 든 액션은 예외를 던진다.
  final Set<String> throwing = {};

  /// `GetTransportInfo` 결과. null이면 응답 없음.
  String? transportState;

  /// `GetPositionInfo` 결과(RelTime, TrackDuration, TrackURI). null이면 응답 없음.
  Map<String, String>? positionInfo;

  /// 비어 있지 않으면 `GetTransportInfo`가 앞에서부터 하나씩 꺼내 쓴다([transportState]보다 우선).
  final Queue<String?> transportStates = Queue();

  /// 비어 있지 않으면 `GetPositionInfo`가 앞에서부터 하나씩 꺼내 쓴다([positionInfo]보다 우선).
  final Queue<Map<String, String>?> positionInfos = Queue();

  /// `GetVolume` 결과. null이면 응답 없음.
  int? volume;

  String? lastStreamUrl;
  DidlMetadata? lastMetadata;
  String? lastNextStreamUrl;
  DidlMetadata? lastNextMetadata;
  String? lastRelTime;
  int? lastVolume;

  final Map<String, Completer<void>> _holds = {};

  /// 받은 액션 이름만(순서대로).
  List<String> get actions => calls.map((c) => c.substring(0, c.indexOf(':'))).toList();

  int countOf(String action) => actions.where((a) => a == action).length;

  /// [action]의 응답을 [release]를 부를 때까지 붙잡아 둔다.
  void hold(String action) => _holds[action] = Completer<void>();

  void release(String action) => _holds.remove(action)?.complete();

  Future<void> _record(String action, String controlUrl) async {
    calls.add('$action:$controlUrl');
    final hold = _holds[action];
    if (hold != null) await hold.future;
    if (throwing.contains(action)) throw StateError('$action 실패(테스트)');
  }

  Future<bool> _command(String action, String controlUrl) async {
    await _record(action, controlUrl);
    return commandResults[action] ?? true;
  }

  @override
  Future<bool> setAVTransportURI(String controlUrl, String streamUrl, DidlMetadata meta) {
    lastStreamUrl = streamUrl;
    lastMetadata = meta;
    return _command('SetAVTransportURI', controlUrl);
  }

  @override
  Future<bool> setNextAVTransportURI(String controlUrl, String streamUrl, DidlMetadata? meta) {
    lastNextStreamUrl = streamUrl;
    lastNextMetadata = meta;
    return _command('SetNextAVTransportURI', controlUrl);
  }

  @override
  Future<bool> play(String controlUrl) => _command('Play', controlUrl);

  @override
  Future<bool> pause(String controlUrl) => _command('Pause', controlUrl);

  @override
  Future<bool> stop(String controlUrl) => _command('Stop', controlUrl);

  @override
  Future<bool> seek(String controlUrl, String relTime) {
    lastRelTime = relTime;
    return _command('Seek', controlUrl);
  }

  @override
  Future<String?> getTransportInfo(String controlUrl) async {
    await _record('GetTransportInfo', controlUrl);
    return transportStates.isNotEmpty ? transportStates.removeFirst() : transportState;
  }

  @override
  Future<Map<String, String>?> getPositionInfo(String controlUrl) async {
    await _record('GetPositionInfo', controlUrl);
    return positionInfos.isNotEmpty ? positionInfos.removeFirst() : positionInfo;
  }

  @override
  Future<int?> getVolume(String controlUrl) async {
    await _record('GetVolume', controlUrl);
    return volume;
  }

  @override
  Future<bool> setVolume(String controlUrl, int volumePercent) {
    lastVolume = volumePercent;
    return _command('SetVolume', controlUrl);
  }
}
