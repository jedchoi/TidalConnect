import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiri_check/kiri_check.dart' show combine2, forAll, property;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tidal_connect_lite/features/dlna/data/dlna_manager.dart';
import 'package:tidal_connect_lite/features/dlna/data/upnp_soap_client.dart';
import 'package:tidal_connect_lite/features/dlna/domain/models/dlna_device.dart';

import '../../helpers/app_overrides.dart';
import '../../helpers/fake_soap_client.dart';
import '../../helpers/generators.dart';
import '../../helpers/pbt_config.dart';
import '../../helpers/playback_fixtures.dart';

// DlnaManager 테스트. 규칙 ID(DM-xx)와 속성 ID(P-DM-x)는
// aidlc-docs/construction/dart-playback-tests/functional-design/ 의
// business-rules.md 2절, business-logic-model.md 5절을 가리킨다.

const _savedUdnKey = 'selected_speaker_udn';
const _metadata = DidlMetadata(title: '곡 101', artist: '가수', durationSeconds: 180, mimeType: 'audio/flac');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  configurePbt();

  late VoidCallback restoreLogs;
  setUpAll(() => restoreLogs = muteDebugLogs());
  tearDownAll(() => restoreLogs());

  late FakeSoapClient soap;
  late FakeSsdpDiscoveryService ssdp;
  final speaker = remoteSpeaker();
  final avUrl = speaker.avTransportControlUrl;
  final renderingUrl = speaker.renderingControlUrl;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    soap = FakeSoapClient();
    ssdp = FakeSsdpDiscoveryService();
  });

  /// [selected]가 선택된 관리자. 생략하면 폰 스피커가 선택된 상태다.
  DlnaManager build({DlnaDevice? selected}) =>
      managerWithSelection(selected ?? DlnaDevice.localSpeaker, soap: soap, ssdp: ssdp);

  Future<String?> savedUdn() async => (await SharedPreferences.getInstance()).getString(_savedUdnKey);

  group('제어 URL 선택', () {
    test('[DM-01] 폰 스피커가 선택되어 있으면 명령은 SOAP 없이 성공으로 끝난다', () async {
      final manager = build();

      expect(await manager.playOnSelectedDevice(streamUrl: proxyUrlFor('101'), metadata: _metadata), isTrue);
      expect(await manager.pauseCurrent(), isTrue);
      expect(await manager.resumeCurrent(), isTrue);
      expect(await manager.seek(10), isTrue);
      expect(await manager.stopCurrent(), isTrue);
      expect(await manager.setVolume(30), isTrue);
      expect(soap.calls, isEmpty);
    });

    test('[DM-02] 폰 스피커가 선택되어 있으면 조회는 SOAP 없이 null이다', () async {
      final manager = build();

      expect(await manager.fetchVolume(), isNull);
      expect(await manager.syncPosition(), isNull);
      expect(await manager.getTransportState(), isNull);
      expect(soap.calls, isEmpty);
    });

    test('[DM-03] 폰 스피커가 선택되어 있으면 다음 곡 등록은 SOAP 없이 false다', () async {
      final manager = build();

      expect(await manager.setNextOnSelectedDevice(streamUrl: proxyUrlFor('102')), isFalse);
      expect(soap.calls, isEmpty);
    });

    test('[DM-04] 전송 명령은 AVTransport 제어 URL로 보낸다', () async {
      final manager = build(selected: speaker);
      soap.positionInfo = positionInfo();

      await manager.pauseCurrent();
      await manager.resumeCurrent();
      await manager.seek(10);
      await manager.stopCurrent();
      await manager.syncPosition();
      await manager.getTransportState();
      await manager.setNextOnSelectedDevice(streamUrl: proxyUrlFor('102'));

      expect(soap.calls, [
        'Pause:$avUrl',
        'Play:$avUrl',
        'Seek:$avUrl',
        'Stop:$avUrl',
        'GetPositionInfo:$avUrl',
        'GetTransportInfo:$avUrl',
        'SetNextAVTransportURI:$avUrl',
      ]);
    });

    test('[DM-04] AVTransport 제어 URL이 없으면 기기 설명 주소로 보낸다', () async {
      final device = remoteSpeaker(avTransportControlUrl: '');
      final manager = build(selected: device);

      await manager.pauseCurrent();
      await manager.playOnSelectedDevice(streamUrl: proxyUrlFor('101'), metadata: _metadata);

      expect(soap.calls.toSet(), hasLength(4));
      expect(soap.calls.every((c) => c.endsWith(':${device.locationUrl}')), isTrue);
    });

    test('[DM-05] 볼륨 명령은 RenderingControl 제어 URL로 보내고, 없으면 기기 설명 주소로 보낸다', () async {
      final manager = build(selected: speaker);
      await manager.fetchVolume();
      await manager.setVolume(30);
      expect(soap.calls, ['GetVolume:$renderingUrl', 'SetVolume:$renderingUrl']);

      soap.calls.clear();
      final device = remoteSpeaker(renderingControlUrl: '');
      manager.selectedDeviceNotifier.value = device;
      await manager.fetchVolume();
      await manager.setVolume(30);
      expect(soap.calls, ['GetVolume:${device.locationUrl}', 'SetVolume:${device.locationUrl}']);
    });

    test('[DM-06] 원격 스피커인데 쓸 주소가 하나도 없으면 SOAP 없이 실패 값을 돌려준다', () async {
      final manager = build(
        selected: remoteSpeaker(locationUrl: '', avTransportControlUrl: '', renderingControlUrl: ''),
      );

      expect(await manager.playOnSelectedDevice(streamUrl: proxyUrlFor('101'), metadata: _metadata), isFalse);
      expect(await manager.pauseCurrent(), isFalse);
      expect(await manager.resumeCurrent(), isFalse);
      expect(await manager.seek(10), isFalse);
      expect(await manager.stopCurrent(), isFalse);
      expect(await manager.setVolume(30), isFalse);
      expect(await manager.setNextOnSelectedDevice(streamUrl: proxyUrlFor('102')), isFalse);
      expect(await manager.fetchVolume(), isNull);
      expect(await manager.syncPosition(), isNull);
      expect(await manager.getTransportState(), isNull);
      expect(soap.calls, isEmpty);
    });
  });

  group('명령 전달', () {
    test('[DM-07] 재생은 Stop, SetAVTransportURI, Play 순서로 보내고 Play 결과를 돌려준다', () async {
      final manager = build(selected: speaker);

      final ok = await manager.playOnSelectedDevice(streamUrl: proxyUrlFor('101'), metadata: _metadata);

      expect(ok, isTrue);
      expect(soap.actions, ['Stop', 'SetAVTransportURI', 'Play']);
      expect(soap.lastStreamUrl, proxyUrlFor('101'));
      expect(soap.lastMetadata, same(_metadata));
    });

    test('[DM-07] Play가 거부되면 false를 돌려준다', () async {
      final manager = build(selected: speaker);
      soap.commandResults['Play'] = false;

      expect(await manager.playOnSelectedDevice(streamUrl: proxyUrlFor('101'), metadata: _metadata), isFalse);
      expect(soap.actions, ['Stop', 'SetAVTransportURI', 'Play']);
    });

    test('[DM-08] SetAVTransportURI가 거부되면 Play를 보내지 않고 false를 돌려준다', () async {
      final manager = build(selected: speaker);
      soap.commandResults['SetAVTransportURI'] = false;

      expect(await manager.playOnSelectedDevice(streamUrl: proxyUrlFor('101'), metadata: _metadata), isFalse);
      expect(soap.actions, ['Stop', 'SetAVTransportURI']);
    });

    test('[DM-09] 처음의 Stop이 거부되어도 계속 진행한다', () async {
      final manager = build(selected: speaker);
      soap.commandResults['Stop'] = false;

      expect(await manager.playOnSelectedDevice(streamUrl: proxyUrlFor('101'), metadata: _metadata), isTrue);
      expect(soap.actions, ['Stop', 'SetAVTransportURI', 'Play']);
    });

    test('[DM-10] SOAP 클라이언트가 예외를 내면 false를 돌려준다', () async {
      final manager = build(selected: speaker);
      soap.throwing.add('SetAVTransportURI');

      expect(await manager.playOnSelectedDevice(streamUrl: proxyUrlFor('101'), metadata: _metadata), isFalse);
      expect(soap.actions, ['Stop', 'SetAVTransportURI']);
    });

    test('[DM-11] 일시정지·재개·정지는 각각 Pause·Play·Stop을 보내고 그 결과를 돌려준다', () async {
      final manager = build(selected: speaker);

      expect(await manager.pauseCurrent(), isTrue);
      expect(await manager.resumeCurrent(), isTrue);
      expect(await manager.stopCurrent(), isTrue);
      expect(soap.actions, ['Pause', 'Play', 'Stop']);

      soap.commandResults.addAll({'Pause': false, 'Play': false, 'Stop': false});
      expect(await manager.pauseCurrent(), isFalse);
      expect(await manager.resumeCurrent(), isFalse);
      expect(await manager.stopCurrent(), isFalse);
    });

    test('[DM-12] 탐색은 초를 HH:MM:SS로 바꿔 Seek에 넘기고 그 결과를 돌려준다', () async {
      final manager = build(selected: speaker);

      expect(await manager.seek(3725), isTrue);
      expect(soap.lastRelTime, '01:02:05');

      await manager.seek(0);
      expect(soap.lastRelTime, '00:00:00');

      await manager.seek(360000);
      expect(soap.lastRelTime, '100:00:00');

      soap.commandResults['Seek'] = false;
      expect(await manager.seek(5), isFalse);
    });

    test('[DM-13] 볼륨 조회는 렌더러 값을 0~100으로 잘라 돌려주고, 응답이 없으면 null이다', () async {
      final manager = build(selected: speaker);

      soap.volume = 42;
      expect(await manager.fetchVolume(), 42);
      soap.volume = 130;
      expect(await manager.fetchVolume(), 100);
      soap.volume = -5;
      expect(await manager.fetchVolume(), 0);
      soap.volume = null;
      expect(await manager.fetchVolume(), isNull);
    });

    test('[DM-14] 볼륨 설정은 0~100으로 자른 값을 SetVolume에 넘기고 그 결과를 돌려준다', () async {
      final manager = build(selected: speaker);

      expect(await manager.setVolume(30), isTrue);
      expect(soap.lastVolume, 30);
      await manager.setVolume(150);
      expect(soap.lastVolume, 100);
      await manager.setVolume(-1);
      expect(soap.lastVolume, 0);

      soap.commandResults['SetVolume'] = false;
      expect(await manager.setVolume(30), isFalse);
    });

    test('[DM-15] 위치 조회는 재생 위치, 곡 길이, 재생 중인 주소를 돌려준다', () async {
      final manager = build(selected: speaker);
      soap.positionInfo = {'RelTime': '0:01:05', 'TrackDuration': '0:03:25', 'TrackURI': proxyUrlFor('101')};

      final position = await manager.syncPosition();

      expect(position!.progressSeconds, 65);
      expect(position.durationSeconds, 205);
      expect(position.trackUri, proxyUrlFor('101'));
    });

    test('[DM-15] 위치 응답이 없으면 null, 주소가 빠져 있으면 빈 문자열이다', () async {
      final manager = build(selected: speaker);

      expect(await manager.syncPosition(), isNull);

      soap.positionInfo = {'RelTime': '0:00:01'};
      final position = await manager.syncPosition();
      expect(position!.trackUri, '');
      expect(position.durationSeconds, 0);
    });

    test('[DM-16] 시간 문자열 해석: 소수 초는 버리고, 해석할 수 없는 값은 0이다', () async {
      final manager = build(selected: speaker);
      const cases = {
        '0:03:25': 205,
        '1:02:05': 3725,
        '0:03:25.500': 205,
        '': 0,
        'NOT_IMPLEMENTED': 0,
        '03:25': 0,
        '1:2:3:4': 0,
        'x:01:05': 65,
        '0:xx:05': 5,
        '0:01:yy': 60,
      };

      for (final entry in cases.entries) {
        soap.positionInfo = {'RelTime': entry.key, 'TrackDuration': entry.key};
        final position = await manager.syncPosition();
        expect(position!.progressSeconds, entry.value, reason: 'RelTime "${entry.key}"');
        expect(position.durationSeconds, entry.value, reason: 'TrackDuration "${entry.key}"');
      }
    });

    test('[DM-17] 다음 곡 등록은 SetNextAVTransportURI를 보내고 그 결과를 돌려준다', () async {
      final manager = build(selected: speaker);

      expect(await manager.setNextOnSelectedDevice(streamUrl: proxyUrlFor('102'), metadata: _metadata), isTrue);
      expect(soap.actions, ['SetNextAVTransportURI']);
      expect(soap.lastNextStreamUrl, proxyUrlFor('102'));
      expect(soap.lastNextMetadata, same(_metadata));

      soap.commandResults['SetNextAVTransportURI'] = false;
      expect(await manager.setNextOnSelectedDevice(streamUrl: proxyUrlFor('103')), isFalse);
    });

    test('[DM-18] 전송 상태 조회는 GetTransportInfo 결과를 그대로 돌려준다', () async {
      final manager = build(selected: speaker);

      soap.transportState = 'PAUSED_PLAYBACK';
      expect(await manager.getTransportState(), 'PAUSED_PLAYBACK');
      soap.transportState = null;
      expect(await manager.getTransportState(), isNull);
    });
  });

  group('탐색과 선택', () {
    test('[DM-19] 원격 스피커를 고르면 선택이 바뀌고 UDN을 저장한다', () async {
      final manager = build();

      manager.selectDevice(speaker);
      await pumpEventQueue();

      expect(manager.selectedDevice, same(speaker));
      expect(await savedUdn(), speaker.udn);
    });

    test('[DM-20] 폰 스피커를 고르면 저장된 UDN을 지운다', () async {
      SharedPreferences.setMockInitialValues({_savedUdnKey: speaker.udn});
      final manager = build(selected: speaker);

      manager.selectDevice(DlnaDevice.localSpeaker);
      await pumpEventQueue();

      expect(manager.selectedDevice.isLocalSpeaker, isTrue);
      expect(await savedUdn(), isNull);
    });

    test('[DM-21] 탐색하는 동안 탐색 중으로 표시하고, 찾는 대로 목록에 더한 뒤 결과 전체로 바꾼다', () async {
      final second = remoteSpeaker(udn: 'uuid:speaker-2', name: '침실 스피커', host: '192.0.2.11');
      ssdp
        ..devices = [speaker, second]
        ..gate = Completer<void>();
      final manager = build();
      final sizes = <int>[];
      manager.devicesNotifier.addListener(() => sizes.add(manager.devices.length));

      final pending = manager.discoverDevices();
      await pumpEventQueue();
      expect(manager.isSearchingNotifier.value, isTrue);
      expect(manager.devices.map((d) => d.udn), ['local_speaker', speaker.udn, second.udn]);

      ssdp.gate!.complete();
      final found = await pending;

      expect(manager.isSearchingNotifier.value, isFalse);
      expect(found.map((d) => d.udn), ['local_speaker', speaker.udn, second.udn]);
      expect(manager.devices.map((d) => d.udn), ['local_speaker', speaker.udn, second.udn]);
      // 폰 스피커만 있는 목록으로 초기화 → 한 대씩 추가 → 결과 전체
      expect(sizes, [1, 2, 3, 3]);
    });

    test('[DM-22] 탐색 중에 다시 부르면 탐색기를 또 부르지 않고 현재 목록을 돌려준다', () async {
      ssdp
        ..devices = [speaker]
        ..gate = Completer<void>();
      final manager = build();

      final first = manager.discoverDevices();
      await pumpEventQueue();
      final second = await manager.discoverDevices();

      expect(ssdp.callCount, 1);
      expect(second.map((d) => d.udn), ['local_speaker', speaker.udn]);

      ssdp.gate!.complete();
      await first;
    });

    test('[DM-23] 탐색기가 예외를 내면 현재 목록을 돌려주고 탐색 중 표시를 끈다', () async {
      ssdp.error = StateError('소켓 오류');
      final manager = build();

      final found = await manager.discoverDevices();

      expect(found.map((d) => d.udn), ['local_speaker']);
      expect(manager.isSearchingNotifier.value, isFalse);
    });

    test('[DM-24] 폰 스피커 상태에서 마지막에 쓴 스피커가 보이면 자동으로 고른다', () async {
      SharedPreferences.setMockInitialValues({_savedUdnKey: speaker.udn});
      ssdp.devices = [speaker];
      final manager = build();

      await manager.discoverDevices();

      expect(manager.selectedDevice.udn, speaker.udn);
      expect(manager.messageNotifier.value, isNull);
    });

    test('[DM-25] 저장된 스피커가 없거나 탐색 결과에 없으면 폰 스피커를 유지한다', () async {
      ssdp.devices = [speaker];
      final withoutSaved = build();
      await withoutSaved.discoverDevices();
      expect(withoutSaved.selectedDevice.isLocalSpeaker, isTrue);

      SharedPreferences.setMockInitialValues({_savedUdnKey: 'uuid:not-found'});
      final savedMissing = build();
      await savedMissing.discoverDevices();
      expect(savedMissing.selectedDevice.isLocalSpeaker, isTrue);
    });

    test('[DM-26] 선택한 스피커가 사라지면 폰 스피커로 바꾸고 안내하되, 저장된 UDN은 남긴다', () async {
      SharedPreferences.setMockInitialValues({_savedUdnKey: speaker.udn});
      final manager = build(selected: speaker);

      await manager.discoverDevices();

      expect(manager.selectedDevice.isLocalSpeaker, isTrue);
      expect(manager.messageNotifier.value, '"${speaker.friendlyName}"을(를) 찾지 못해 폰 스피커로 전환했습니다.');
      expect(await savedUdn(), speaker.udn);
    });

    test('[DM-27] 선택한 스피커가 탐색 결과에 있으면 선택을 유지하고 안내하지 않는다', () async {
      ssdp.devices = [speaker];
      final manager = build(selected: speaker);

      await manager.discoverDevices();

      expect(manager.selectedDevice, same(speaker));
      expect(manager.messageNotifier.value, isNull);
    });

    test('[DM-28] 재생 중에는 스피커가 사라져도, 저장된 스피커가 보여도 선택을 바꾸지 않는다', () async {
      final missing = build(selected: speaker)..isPlaybackActive = () => true;
      await missing.discoverDevices();
      expect(missing.selectedDevice, same(speaker));
      expect(missing.messageNotifier.value, isNull);

      SharedPreferences.setMockInitialValues({_savedUdnKey: speaker.udn});
      ssdp.devices = [speaker];
      final local = build()..isPlaybackActive = () => true;
      await local.discoverDevices();
      expect(local.selectedDevice.isLocalSpeaker, isTrue);
    });

    test('[DM-29] 사라져서 폰 스피커로 바뀐 스피커가 다시 보이면 다시 고른다', () async {
      final manager = build();
      manager.selectDevice(speaker);
      await pumpEventQueue();

      await manager.discoverDevices();
      expect(manager.selectedDevice.isLocalSpeaker, isTrue);

      ssdp.devices = [speaker];
      await manager.discoverDevices();
      expect(manager.selectedDevice.udn, speaker.udn);
    });
  });

  group('속성', () {
    /// 속성의 예시마다 새 관리자와 새 SOAP 클라이언트를 쓴다.
    (DlnaManager, FakeSoapClient) fresh() {
      final client = FakeSoapClient();
      return (managerWithSelection(remoteSpeaker(), soap: client), client);
    }

    String hms(int seconds) => '${seconds ~/ 3600}:${(seconds % 3600 ~/ 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';

    /// [situation]대로 저장소·탐색 결과·선택·재생 여부를 준비한 관리자.
    ///
    /// 원격 스피커가 선택된 상황에서는 저장된 UDN을 그 스피커의 것으로 둔다. 앱에서 선택은
    /// `selectDevice`(선택한 UDN을 저장)와 탐색 뒤 정리로만 바뀌므로, 선택된 원격 스피커와
    /// 저장된 UDN이 서로 다른 기기인 상태는 생기지 않는다. `situation.saved`는 폰 스피커가
    /// 선택된 상황에서만 쓴다.
    DlnaManager arrange(DiscoverySituation situation) {
      final found = situation.found;
      DlnaDevice? picked() => found.isEmpty ? null : found[situation.pick % found.length];
      final selection = switch (situation.selection) {
        DeviceRef.none => DlnaDevice.localSpeaker,
        DeviceRef.inResults => picked() ?? DlnaDevice.localSpeaker,
        DeviceRef.outsideResults => remoteSpeaker(udn: 'uuid:selected-but-not-found'),
      };
      final savedUdn = !selection.isLocalSpeaker
          ? selection.udn
          : switch (situation.saved) {
              DeviceRef.none => null,
              DeviceRef.inResults => picked()?.udn,
              DeviceRef.outsideResults => 'uuid:saved-but-not-found',
            };
      SharedPreferences.setMockInitialValues({if (savedUdn != null) _savedUdnKey: savedUdn});
      final manager = managerWithSelection(
        selection,
        soap: FakeSoapClient(),
        ssdp: FakeSsdpDiscoveryService()..devices = found,
      );
      return manager..isPlaybackActive = () => situation.playbackActive;
    }

    property('[P-DM-1] 초를 시간 문자열로 보냈다가 다시 읽으면 같은 초가 된다', () {
      forAll(seconds(), (s) async {
        final (manager, client) = fresh();

        await manager.seek(s);
        client.positionInfo = {'RelTime': client.lastRelTime!};
        final position = await manager.syncPosition();

        expect(position!.progressSeconds, s, reason: client.lastRelTime);
      });
    });

    property('[P-DM-2] 탐색 명령의 시간 문자열은 항상 HH:MM:SS 형식이다', () {
      forAll(seconds(), (s) async {
        final (manager, client) = fresh();

        await manager.seek(s);

        final match = RegExp(r'^(\d{2,}):(\d{2}):(\d{2})$').firstMatch(client.lastRelTime!);
        expect(match, isNotNull, reason: client.lastRelTime);
        expect(int.parse(match!.group(2)!), lessThan(60));
        expect(int.parse(match.group(3)!), lessThan(60));
      });
    });

    property('[P-DM-3] 어떤 정수 볼륨이든 스피커에는 0~100으로 자른 값이 가고, 조회 값도 같은 방식으로 자른다', () {
      forAll(volumes(), (v) async {
        final (manager, client) = fresh();
        final clamped = v < 0 ? 0 : (v > 100 ? 100 : v);

        await manager.setVolume(v);
        expect(client.lastVolume, clamped);

        client.volume = v;
        expect(await manager.fetchVolume(), clamped);
      });
    });

    property('[P-DM-4] 시간 문자열에 소수 초가 붙어도 해석 결과가 같다', () {
      forAll(combine2(seconds(), millis()), (input) async {
        final (s, ms) = input;
        final (manager, client) = fresh();

        client.positionInfo = {'RelTime': '${hms(s)}.${ms.toString().padLeft(3, '0')}', 'TrackDuration': hms(s)};
        final position = await manager.syncPosition();

        expect(position!.progressSeconds, s);
        expect(position.durationSeconds, s);
      });
    });

    property('[P-DM-4] 어떤 문자열이 와도 위치 조회는 예외를 내지 않는다', () {
      forAll(combine2(timeLikeStrings(), timeLikeStrings()), (input) async {
        final (manager, client) = fresh();

        client.positionInfo = {'RelTime': input.$1, 'TrackDuration': input.$2};

        expect(await manager.syncPosition(), isNotNull, reason: '$input');
      });
    });

    property('[P-DM-5] 같은 기기를 두 번 골라도 한 번 고른 것과 선택·저장 결과가 같다', () {
      forAll(remoteDevices(), (device) async {
        SharedPreferences.setMockInitialValues({});
        final (manager, _) = fresh();

        manager.selectDevice(device);
        await pumpEventQueue(times: 5);
        final onceSelected = manager.selectedDevice.udn;
        final onceSaved = (await SharedPreferences.getInstance()).getString(_savedUdnKey);

        manager.selectDevice(device);
        await pumpEventQueue(times: 5);

        expect(manager.selectedDevice.udn, onceSelected);
        expect((await SharedPreferences.getInstance()).getString(_savedUdnKey), onceSaved);
        expect(onceSaved, device.udn);
      });
    });

    property('[P-DM-5] 같은 탐색 결과로 두 번 탐색해도 한 번 탐색한 것과 선택이 같다', () {
      forAll(discoverySituations(), (situation) async {
        final manager = arrange(situation);

        await manager.discoverDevices();
        final once = manager.selectedDevice.udn;
        await manager.discoverDevices();

        expect(manager.selectedDevice.udn, once, reason: '$situation');
      });
    });

    property('[P-DM-6] 탐색 뒤의 선택은 폰 스피커이거나 탐색 결과 안의 기기이고, 재생 중이면 바뀌지 않는다', () {
      forAll(discoverySituations(), (situation) async {
        final manager = arrange(situation);
        final before = manager.selectedDevice.udn;

        await manager.discoverDevices();

        final after = manager.selectedDevice;
        if (situation.playbackActive) {
          expect(after.udn, before, reason: '$situation');
        } else {
          final foundUdns = situation.found.map((d) => d.udn);
          expect(after.isLocalSpeaker || foundUdns.contains(after.udn), isTrue, reason: '$situation → ${after.udn}');
        }
      });
    });
  });
}
