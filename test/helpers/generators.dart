import 'package:kiri_check/kiri_check.dart' as kc;
import 'package:tidal_connect_lite/features/dlna/domain/models/dlna_device.dart';
import 'package:tidal_connect_lite/features/tidal_api/domain/models/media_item.dart';

// 속성 기반 테스트의 도메인 생성기.
// 범위는 aidlc-docs/construction/dart-playback-tests/functional-design/domain-entities.md 3절을 따른다.
// 값은 kiri_check의 조합 함수로만 만든다(직접 난수를 쓰면 실패 입력을 줄여 주지 못한다).

final _ascii = kc.CharacterEncoding.ascii;

/// 값이 없을 수도 있는 필드. 넷 중 하나꼴로 null.
kc.Arbitrary<T?> optional<T>(kc.Arbitrary<T> arbitrary) =>
    kc.frequency([(1, kc.null_()), (3, arbitrary)]).map((v) => v as T?);

/// 곡 ID: 숫자 1~12자리.
kc.Arbitrary<String> trackIds() => kc.string(minLength: 1, maxLength: 12, characterSet: kc.CharacterSet.digit(_ascii));

/// 제목·이름: 빈 문자열, 한글, 공백, XML에서 뜻이 있는 기호를 포함한다.
kc.Arbitrary<String> labels() => kc.string(
      maxLength: 24,
      characterSet: kc.CharacterSet.fromCharacters('가나다라마바사아자차 ABCxyz0189&<>"\'·-()!?'),
    );

/// 커버 주소: 빈 문자열이거나 유효한 https 주소.
kc.Arbitrary<String> coverUrls() => kc.frequency([
      (1, kc.constant('')),
      (3, trackIds().map((id) => 'https://resources.example.test/images/$id/640x640.jpg')),
    ]).map((v) => v as String);

/// 곡. 길이는 0(모름)~36000초.
kc.Arbitrary<MediaTrack> tracks() => kc
    .combine6(trackIds(), labels(), labels(), labels(), coverUrls(), kc.integer(min: 0, max: 36000))
    .map((v) => MediaTrack(
          id: v.$1,
          title: v.$2,
          artistName: v.$3,
          albumTitle: v.$4,
          coverUrl: v.$5,
          durationSeconds: v.$6,
        ));

/// 곡 목록: 0~50곡.
kc.Arbitrary<List<MediaTrack>> trackLists() => kc.list(tracks(), minLength: 0, maxLength: 50);

/// 재생 위치·길이(초): 0~359999(99:59:59).
kc.Arbitrary<int> seconds() => kc.integer(min: 0, max: 359999);

/// 볼륨 입력: 범위(0~100) 밖을 포함하는 정수.
kc.Arbitrary<int> volumes() => kc.integer(min: -1000, max: 1000);

/// 소수 초(밀리초 0~999).
kc.Arbitrary<int> millis() => kc.integer(min: 0, max: 999);

/// 시간 문자열 자리에 올 수 있는 임의의 문자열. 콜론과 숫자가 자주 나오게 한다.
kc.Arbitrary<String> timeLikeStrings() => kc.string(
      maxLength: 20,
      characterSet: kc.CharacterSet.fromCharacters('0123456789::::..- NOT_IMPLEMENTEDxyz'),
    );

/// 플레이어 상태 이름: 알려진 값과 임의의 대문자 문자열.
kc.Arbitrary<String> playerStates() => kc.frequency([
      (3, kc.constantFrom(['PLAYING', 'STALLED', 'NOT_PLAYING', 'IDLE'])),
      (1, kc.string(maxLength: 12, characterSet: kc.CharacterSet.upper(_ascii))),
    ]).map((v) => v as String);

/// 네이티브 플레이어 이벤트 맵.
///
/// `type`은 알려진 5종, `phoneVolume`, 임의 문자열, 없음 가운데 하나다.
/// 그 밖의 필드는 각각 있거나 없고, 있으면 채널 계약의 타입이다(숫자는 0 이상).
kc.Arbitrary<Map<String, dynamic>> nativeEvents() {
  final types = kc.frequency([
    (6, kc.constantFrom(['state', 'position', 'transition', 'ended', 'error'])),
    (1, kc.constant('phoneVolume')),
    (1, kc.string(maxLength: 10, characterSet: kc.CharacterSet.lower(_ascii))),
    (1, kc.null_()),
  ]).map((v) => v as String?);
  final quality = kc.combine5(
    optional(kc.constantFrom(['LOW', 'HIGH', 'LOSSLESS', 'HI_RES_LOSSLESS'])),
    optional(kc.constantFrom([16, 24])),
    optional(kc.constantFrom([44100, 48000, 96000, 192000])),
    optional(kc.constantFrom(['flac', 'aac', 'mqa'])),
    optional(kc.boolean()),
  );
  final error = kc.combine2(optional(kc.constantFrom(['PRIVILEGES_REVOKED', 'NETWORK', 'E1'])), optional(labels()));
  return kc
      .combine7(
        types,
        optional(playerStates()),
        optional(kc.integer(min: 0, max: 36000000)),
        optional(trackIds()),
        optional(kc.integer(min: 0, max: 36000000)),
        quality,
        error,
      )
      .map((v) => <String, dynamic>{
            if (v.$1 != null) 'type': v.$1,
            if (v.$2 != null) 'state': v.$2,
            if (v.$3 != null) 'positionMs': v.$3,
            if (v.$4 != null) 'trackId': v.$4,
            if (v.$5 != null) 'durationMs': v.$5,
            if (v.$6.$1 != null) 'audioQuality': v.$6.$1,
            if (v.$6.$2 != null) 'bitDepth': v.$6.$2,
            if (v.$6.$3 != null) 'sampleRate': v.$6.$3,
            if (v.$6.$4 != null) 'codec': v.$6.$4,
            if (v.$6.$5 != null) 'preview': v.$6.$5,
            if (v.$7.$1 != null) 'code': v.$7.$1,
            if (v.$7.$2 != null) 'message': v.$7.$2,
          });
}

/// 폰 출력에 가하는 동작 하나(pending seek 속성용).
sealed class PhoneAction {
  const PhoneAction();
}

class PhonePlay extends PhoneAction {
  const PhonePlay(this.startSeconds);
  final int startSeconds;
  @override
  String toString() => 'play(start: ${startSeconds}s)';
}

class PhoneStateEvent extends PhoneAction {
  const PhoneStateEvent(this.state);
  final String state;
  @override
  String toString() => 'state($state)';
}

class PhoneStop extends PhoneAction {
  const PhoneStop();
  @override
  String toString() => 'stop()';
}

/// 폰 출력 동작 순서: 0~30개. 시작 위치는 0~600초이고 0이 자주 나온다.
kc.Arbitrary<List<PhoneAction>> phoneActionSequences() {
  final start = kc.frequency([(1, kc.constant(0)), (2, kc.integer(min: 1, max: 600))]).map((v) => v as int);
  final action = kc.frequency([
    (3, start.map<PhoneAction>(PhonePlay.new)),
    (4, playerStates().map<PhoneAction>(PhoneStateEvent.new)),
    (1, kc.constant<PhoneAction>(const PhoneStop())),
  ]).map((v) => v as PhoneAction);
  return kc.list(action, minLength: 0, maxLength: 30);
}

/// 문서용 예약 대역의 IPv4 주소.
kc.Arbitrary<String> ipv4Hosts() => kc
    .combine2(kc.constantFrom(['192.0.2', '198.51.100', '203.0.113']), kc.integer(min: 1, max: 254))
    .map((v) => '${v.$1}.${v.$2}');

kc.Arbitrary<int> ports() => kc.integer(min: 1, max: 65535);

/// 원격 스피커. 제어 URL 두 개는 각각 있거나 빈 문자열이다.
kc.Arbitrary<DlnaDevice> remoteDevices() => kc
    .combine6(
      kc.string(minLength: 8, maxLength: 16, characterSet: kc.CharacterSet.hexDigit()),
      labels(),
      ipv4Hosts(),
      ports(),
      kc.boolean(),
      kc.boolean(),
    )
    .map((v) => DlnaDevice(
          udn: 'uuid:${v.$1}',
          friendlyName: v.$2,
          locationUrl: 'http://${v.$3}:${v.$4}/desc.xml',
          avTransportControlUrl: v.$5 ? 'http://${v.$3}:${v.$4}/AVTransport/control' : '',
          renderingControlUrl: v.$6 ? 'http://${v.$3}:${v.$4}/RenderingControl/control' : '',
        ));

/// 탐색 직전의 상황(선택 정리 속성용).
class DiscoverySituation {
  const DiscoverySituation({
    required this.found,
    required this.selection,
    required this.saved,
    required this.pick,
    required this.playbackActive,
  });

  /// 탐색 결과에 나올 원격 기기(UDN 중복 없음).
  final List<DlnaDevice> found;

  /// 탐색 전 선택: 폰 스피커 / 결과 안의 기기 / 결과에 없는 기기.
  final DeviceRef selection;

  /// 저장된 UDN: 없음 / 결과 안의 기기 / 결과에 없는 기기.
  final DeviceRef saved;

  /// 결과 안의 기기를 고를 때 쓰는 번호(결과 개수로 나눈 나머지).
  final int pick;

  final bool playbackActive;

  @override
  String toString() => 'found=${found.map((d) => d.udn).toList()}, selection=$selection, saved=$saved, '
      'pick=$pick, playbackActive=$playbackActive';
}

enum DeviceRef { none, inResults, outsideResults }

kc.Arbitrary<DiscoverySituation> discoverySituations() => kc
    .combine5(
      kc.list(remoteDevices(), minLength: 0, maxLength: 5, uniqueBy: (a, b) => a.udn == b.udn),
      kc.constantFrom(DeviceRef.values),
      kc.constantFrom(DeviceRef.values),
      kc.integer(min: 0, max: 4),
      kc.boolean(),
    )
    .map((v) => DiscoverySituation(found: v.$1, selection: v.$2, saved: v.$3, pick: v.$4, playbackActive: v.$5));

/// 스피커가 폴링 한 번에 돌려주는 응답.
class PollResponse {
  const PollResponse({this.state, this.relSeconds, this.durationSeconds = 0});

  /// 전송 상태. null이면 응답 없음.
  final String? state;

  /// 재생 위치(초). null이면 위치 응답 없음.
  final int? relSeconds;

  /// 렌더러가 알려준 곡 길이(초). 0이면 모름.
  final int durationSeconds;

  @override
  String toString() => 'poll(state: $state, position: ${relSeconds == null ? 'none' : '$relSeconds/$durationSeconds'})';
}

/// 폴링 응답 순서: 0~30개. [trackSeconds]는 재생 중인 곡의 길이다.
kc.Arbitrary<List<PollResponse>> pollSequences(int trackSeconds) {
  final state = kc.frequency([
    (4, kc.constant('PLAYING')),
    (2, kc.constant('STOPPED')),
    (1, kc.constantFrom(['NO_MEDIA_PRESENT', 'PAUSED_PLAYBACK', 'TRANSITIONING'])),
    (1, kc.string(minLength: 1, maxLength: 8, characterSet: kc.CharacterSet.upper(_ascii))),
    (3, kc.null_()),
  ]).map((v) => v as String?);
  final position = optional(
    kc.combine2(kc.integer(min: 0, max: trackSeconds + 10), kc.constantFrom([0, trackSeconds])),
  );
  final response = kc.combine2(state, position).map(
        (v) => PollResponse(state: v.$1, relSeconds: v.$2?.$1, durationSeconds: v.$2?.$2 ?? 0),
      );
  return kc.list(response, minLength: 0, maxLength: 30);
}

/// 시작 오프셋이 있는 흐름에서 스피커가 알려주는 위치의 순서(위치 보정 속성용).
class OffsetFlow {
  const OffsetFlow({required this.offsetSeconds, required this.relSeconds});

  /// 시작 오프셋(초). 10 이상.
  final int offsetSeconds;

  /// 스피커가 차례로 알려주는 `RelTime`(초). 모두 0보다 크고 줄어들지 않는다. 1개 이상.
  final List<int> relSeconds;

  @override
  String toString() => 'offset=${offsetSeconds}s, rel=$relSeconds';
}

/// 시작 오프셋 10~3600초. 첫 `RelTime`은 셋 중 둘꼴로 판정 경계(오프셋 - 2초) 근처(±6초)이고,
/// 나머지는 1~3600초다. 이후 값은 0~30초씩 늘어난다(최대 8개).
kc.Arbitrary<OffsetFlow> offsetFlows() => kc
        .combine5(
      kc.integer(min: 10, max: 3600),
      kc.frequency([(2, kc.constant(true)), (1, kc.constant(false))]).map((v) => v as bool),
      kc.integer(min: -6, max: 6),
      kc.integer(min: 1, max: 3600),
      kc.list(kc.integer(min: 0, max: 30), minLength: 0, maxLength: 8),
    )
        .map((v) {
      final nearBoundary = v.$1 - 2 + v.$3;
      final rel = <int>[v.$2 ? (nearBoundary < 1 ? 1 : nearBoundary) : v.$4];
      for (final step in v.$5) {
        rel.add(rel.last + step);
      }
      return OffsetFlow(offsetSeconds: v.$1, relSeconds: rel);
    });

/// 재생 시작 요청 하나(시작 위치 속성용).
class StartRequest {
  const StartRequest({required this.dash, required this.startPosition});

  /// DASH 곡이면 true, 단일 파일 곡이면 false.
  final bool dash;

  final Duration startPosition;

  @override
  String toString() => '${dash ? 'dash' : 'direct'} start=${startPosition.inMilliseconds}ms';
}

/// 시작 위치는 넷 중 하나꼴로 0이다. DASH 곡은 0~3599999밀리초,
/// 단일 파일 곡은 0이거나 1000밀리초 이상이다(1초 미만의 양수는 만들지 않는다. red-seam-table-dart.md "정한 것").
kc.Arbitrary<StartRequest> startRequests() => kc
        .combine3(
      kc.boolean(),
      kc.frequency([(1, kc.constant(0)), (3, kc.integer(min: 1, max: 3599))]).map((v) => v as int),
      millis(),
    )
        .map((v) {
      final (dash, wholeSeconds, extraMillis) = v;
      final ms = wholeSeconds * 1000 + (dash || wholeSeconds > 0 ? extraMillis : 0);
      return StartRequest(dash: dash, startPosition: Duration(milliseconds: ms));
    });

/// 렌더러가 주소의 표기를 바꿔 돌려주는 경우: 스킴·호스트·포트와 앞뒤 공백만 다르다.
class UrlRewrite {
  const UrlRewrite({
    required this.scheme,
    required this.host,
    required this.port,
    required this.leading,
    required this.trailing,
  });

  final String scheme;
  final String host;
  final int port;
  final String leading;
  final String trailing;

  /// [original]의 경로와 쿼리는 그대로 두고 나머지를 바꾼 주소.
  String apply(String original) {
    final uri = Uri.parse(original);
    return '$leading${uri.replace(scheme: scheme, host: host, port: port)}$trailing';
  }

  @override
  String toString() => 'rewrite($scheme://$host:$port, leading: ${leading.length}, trailing: ${trailing.length})';
}

kc.Arbitrary<UrlRewrite> urlRewrites() {
  final host = kc.frequency([
    (2, ipv4Hosts()),
    (1, kc.constantFrom(['speaker.test', 'phone.test']))
  ]).map(
    (v) => v as String,
  );
  final whitespace = kc.constantFrom(['', ' ', '  ', '\n', '\t ']);
  return kc.combine5(kc.constantFrom(['http', 'https']), host, ports(), whitespace, whitespace).map(
        (v) => UrlRewrite(scheme: v.$1, host: v.$2, port: v.$3, leading: v.$4, trailing: v.$5),
      );
}

/// 다른 곡의 주소로 만드는 변형: 경로의 한 글자를 바꾸거나, 쿼리를 붙이거나, 둘 다.
class UrlMismatch {
  const UrlMismatch({required this.changePath, required this.addQuery, required this.position});

  final bool changePath;
  final bool addQuery;

  /// 경로에서 바꿀 글자의 위치(파일 이름 길이로 나눈 나머지).
  final int position;

  String apply(String original) {
    final uri = Uri.parse(original);
    var path = uri.path;
    if (changePath) {
      // 마지막 경로 조각(토큰.확장자)의 토큰 부분에서 한 글자를 다른 글자로 바꾼다.
      final slash = path.lastIndexOf('/') + 1;
      final dot = path.lastIndexOf('.');
      final tokenLength = dot - slash;
      final index = slash + position % tokenLength;
      final replacement = path[index] == 'z' ? 'y' : 'z';
      path = path.replaceRange(index, index + 1, replacement);
    }
    return uri.replace(path: path, query: addQuery ? 'v=2' : null).toString();
  }

  @override
  String toString() => 'mismatch(changePath: $changePath, addQuery: $addQuery, position: $position)';
}

kc.Arbitrary<UrlMismatch> urlMismatches() => kc
    .combine2(kc.constantFrom([(true, false), (false, true), (true, true)]), kc.integer(min: 0, max: 63))
    .map((v) => UrlMismatch(changePath: v.$1.$1, addQuery: v.$1.$2, position: v.$2));
