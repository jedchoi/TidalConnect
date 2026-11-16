import 'package:flutter/foundation.dart';
import '../../../core/utils/app_logger.dart';
import '../../tidal_api/data/tidal_api_client.dart';

/// 로그인한 계정의 즐겨찾기 ID를 들고 있고, 하트 버튼의 추가·삭제를 처리한다.
///
/// 누르는 즉시 화면에 반영하고(낙관적 갱신), 서버 요청이 실패하면 되돌린다.
class FavoritesRepository extends ChangeNotifier {
  FavoritesRepository({required TidalApiClient api}) : _api = api;

  final TidalApiClient _api;
  String? _userId;
  Map<FavoriteType, Set<String>> _ids = {for (final t in FavoriteType.values) t: <String>{}};
  final Set<String> _pending = {};
  int _loadSeq = 0;

  /// 즐겨찾기를 바꾼 횟수. 목록 화면이 이 값의 변화를 보고 다시 불러온다.
  int _revision = 0;
  int get revision => _revision;

  /// 로그인 상태라 하트 버튼을 보여줄 수 있는지.
  bool get isAvailable => _userId != null;

  bool isFavorite(FavoriteType type, String id) => _ids[type]!.contains(id);

  /// 요청이 진행 중인 항목. 버튼을 잠시 비활성화한다.
  bool isPending(FavoriteType type, String id) => _pending.contains('${type.name}:$id');

  /// 로그인 사용자가 바뀌면 호출한다. null이면 비운다.
  Future<void> setUser(String? userId) async {
    if (userId == _userId) return;
    _userId = userId;
    final seq = ++_loadSeq;
    _ids = {for (final t in FavoriteType.values) t: <String>{}};
    notifyListeners();
    if (userId == null) return;
    try {
      final ids = await _api.getFavoriteIds(userId: userId);
      if (seq != _loadSeq) return;
      _ids = {for (final t in FavoriteType.values) t: {...?ids[t]}};
      notifyListeners();
    } catch (e) {
      AppLogger.log('FAVORITES', '즐겨찾기 ID 조회 실패: $e', type: LogType.warning);
    }
  }

  /// 즐겨찾기를 켜고 끈다. 성공하면 true, 실패해 되돌렸으면 false.
  Future<bool> toggle(FavoriteType type, String id) async {
    final userId = _userId;
    final key = '${type.name}:$id';
    if (userId == null || id.isEmpty || _pending.contains(key)) return false;
    final wasFavorite = isFavorite(type, id);
    _pending.add(key);
    _set(type, id, !wasFavorite);
    try {
      if (wasFavorite) {
        await _api.removeFavorite(userId: userId, type: type, id: id);
      } else {
        await _api.addFavorite(userId: userId, type: type, id: id);
      }
      _revision++;
      return true;
    } catch (e) {
      AppLogger.log('FAVORITES', '즐겨찾기 변경 실패 (${type.name} $id): $e', type: LogType.error);
      if (userId == _userId) _set(type, id, wasFavorite);
      return false;
    } finally {
      _pending.remove(key);
      notifyListeners();
    }
  }

  void _set(FavoriteType type, String id, bool favorite) {
    final ids = _ids[type]!;
    favorite ? ids.add(id) : ids.remove(id);
    notifyListeners();
  }
}
