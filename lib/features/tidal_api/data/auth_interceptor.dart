import 'package:dio/dio.dart';
import '../../auth/data/tidal_auth_repository.dart';
import 'api_failure.dart';

/// 모든 TIDAL API 요청에 토큰과 계정 국가 코드를 붙인다.
///
/// 401을 받으면 토큰을 한 번 갱신해 같은 요청을 다시 보낸다. 다시 실패하면 오류를 그대로 넘긴다.
class AuthInterceptor extends Interceptor {
  final TidalAuthRepository _auth;
  final Dio _dio;

  static const _retriedKey = 'auth_retried';

  AuthInterceptor(this._auth, this._dio);

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _auth.getCatalogToken();
    if (token == null) {
      handler.reject(DioException(
        requestOptions: options,
        error: const ApiFailure(ApiFailureKind.network, 'TIDAL 인증 토큰을 받지 못했습니다. 네트워크를 확인해 주세요.'),
      ));
      return;
    }
    options.headers['Authorization'] = 'Bearer $token';
    // 토큰을 받은 뒤라 저장된 계정 정보가 로드되어 있다. 호출자가 정한 값이 있으면 그대로 둔다.
    options.queryParameters.putIfAbsent('countryCode', () => _auth.countryCode);
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    if (err.response?.statusCode != 401 || options.extra[_retriedKey] == true) {
      handler.next(err);
      return;
    }
    final token = await _auth.recoverFromUnauthorized();
    if (token == null) {
      handler.next(err);
      return;
    }
    options.extra[_retriedKey] = true;
    options.headers['Authorization'] = 'Bearer $token';
    try {
      handler.resolve(await _dio.fetch(options));
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}
