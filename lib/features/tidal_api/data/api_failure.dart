import 'package:dio/dio.dart';

enum ApiFailureKind { network, unauthorized, server, parse }

/// TIDAL API 호출 실패. 화면은 [kind]로 "오류"와 "비어 있음"을 구분해 보여준다.
class ApiFailure implements Exception {
  final ApiFailureKind kind;
  final String message;
  final int? statusCode;

  const ApiFailure(this.kind, this.message, {this.statusCode});

  factory ApiFailure.fromDio(DioException e) {
    final status = e.response?.statusCode;
    if (e.error is ApiFailure) return e.error as ApiFailure;
    if (status == 401 || status == 403) {
      return ApiFailure(ApiFailureKind.unauthorized, '인증이 만료되었거나 권한이 없습니다. 다시 로그인해 주세요.', statusCode: status);
    }
    if (status != null) {
      return ApiFailure(ApiFailureKind.server, 'TIDAL 서버 오류가 발생했습니다. (HTTP $status)', statusCode: status);
    }
    return const ApiFailure(ApiFailureKind.network, '네트워크에 연결할 수 없습니다. 연결 상태를 확인해 주세요.');
  }

  @override
  String toString() => 'ApiFailure(${kind.name}, $statusCode): $message';
}
