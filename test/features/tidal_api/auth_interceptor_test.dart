import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tidal_connect_lite/features/tidal_api/data/api_failure.dart';
import 'package:tidal_connect_lite/features/tidal_api/data/auth_interceptor.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeAuthRepository auth;
  late List<String?> sentAuthHeaders;

  Dio build(List<int> statuses) {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'));
    var call = 0;
    dio.httpClientAdapter = FakeAdapter((options) async {
      sentAuthHeaders.add(options.headers['Authorization'] as String?);
      final status = statuses[call < statuses.length ? call : statuses.length - 1];
      call++;
      return jsonBody({'ok': status == 200}, status: status);
    });
    dio.interceptors.add(AuthInterceptor(auth, dio));
    return dio;
  }

  setUp(() {
    auth = FakeAuthRepository();
    sentAuthHeaders = [];
  });

  test('요청마다 Bearer 토큰을 붙인다', () async {
    final dio = build([200]);
    await dio.get('/x');
    expect(sentAuthHeaders, ['Bearer token-1']);
    expect(auth.recoverCount, 0);
  });

  test('계정 국가 코드를 붙이되 호출자가 정한 값은 바꾸지 않는다', () async {
    final dio = build([200]);
    final first = await dio.get('/x');
    expect(first.requestOptions.queryParameters['countryCode'], auth.countryCode);
    final second = await dio.get('/x', queryParameters: {'countryCode': 'SE'});
    expect(second.requestOptions.queryParameters['countryCode'], 'SE');
  });

  test('401이면 토큰을 갱신해 한 번 다시 보낸다', () async {
    final dio = build([401, 200]);
    final res = await dio.get('/x');
    expect(res.statusCode, 200);
    expect(sentAuthHeaders, ['Bearer token-1', 'Bearer token-2']);
    expect(auth.recoverCount, 1);
  });

  test('재시도도 401이면 더 반복하지 않고 오류를 넘긴다', () async {
    final dio = build([401, 401, 200]);
    await expectLater(
      dio.get('/x'),
      throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'status', 401)),
    );
    expect(sentAuthHeaders.length, 2);
    expect(auth.recoverCount, 1);
  });

  test('토큰 갱신에 실패하면 재시도하지 않는다', () async {
    auth.recoveredToken = null;
    final dio = build([401, 200]);
    await expectLater(dio.get('/x'), throwsA(isA<DioException>()));
    expect(sentAuthHeaders.length, 1);
  });

  test('401이 아닌 오류는 갱신 없이 그대로 넘긴다', () async {
    final dio = build([500]);
    await expectLater(dio.get('/x'), throwsA(isA<DioException>()));
    expect(auth.recoverCount, 0);
  });

  test('토큰이 없으면 요청을 보내지 않고 ApiFailure로 거절한다', () async {
    auth.catalogToken = null;
    final dio = build([200]);
    await expectLater(
      dio.get('/x'),
      throwsA(isA<DioException>().having((e) => e.error, 'error', isA<ApiFailure>())),
    );
    expect(sentAuthHeaders, isEmpty);
  });
}
