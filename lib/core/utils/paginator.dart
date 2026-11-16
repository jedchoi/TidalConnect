import 'package:flutter/widgets.dart';
import '../../features/tidal_api/data/tidal_api_client.dart';

/// 목록을 페이지 단위로 이어 받는다. 화면은 [items]를 그리고 스크롤이 끝에 닿으면 [loadMore]를 부른다.
class Paginator<T> extends ChangeNotifier {
  Paginator(this._fetch);

  final Future<PageResult<T>> Function(int offset) _fetch;

  List<T> _items = const [];
  List<T> get items => _items;

  int? _total;

  /// 서버가 알려준 전체 개수. 모르면 지금까지 받은 개수.
  int get totalCount => _total ?? _items.length;

  bool _hasMore = false;
  bool get hasMore => _hasMore;

  bool _isLoadingMore = false;
  bool get isLoadingMore => _isLoadingMore;

  /// 다음 페이지를 받다가 실패했는지. 다시 [loadMore]를 부르면 재시도한다.
  bool _loadMoreFailed = false;
  bool get loadMoreFailed => _loadMoreFailed;

  /// [refresh]가 다시 불리면 진행 중이던 이전 요청의 결과를 버린다.
  int _generation = 0;
  bool _disposed = false;

  /// 첫 페이지를 받는다. 실패하면 예외를 던진다(화면이 오류 화면을 보여준다).
  Future<void> refresh() async {
    final gen = ++_generation;
    _isLoadingMore = false;
    _loadMoreFailed = false;
    final page = await _fetch(0);
    if (gen != _generation || _disposed) return;
    _items = List.unmodifiable(page.items);
    _total = page.total;
    _hasMore = page.hasMore;
    notifyListeners();
  }

  /// 다음 페이지를 받는다. 이미 받는 중이거나 더 없으면 아무 일도 하지 않는다.
  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    final gen = _generation;
    _isLoadingMore = true;
    _loadMoreFailed = false;
    notifyListeners();
    try {
      final page = await _fetch(_items.length);
      if (gen != _generation || _disposed) return;
      _items = List.unmodifiable([..._items, ...page.items]);
      _total = page.total ?? _total;
      _hasMore = page.hasMore;
    } catch (_) {
      if (gen != _generation || _disposed) return;
      _loadMoreFailed = true;
    } finally {
      if (gen == _generation && !_disposed) {
        _isLoadingMore = false;
        notifyListeners();
      }
    }
  }

  /// 스크롤 알림을 받아 끝에 가까우면 다음 페이지를 요청한다. 화면의 NotificationListener에 넘긴다.
  /// [axis]와 다른 방향의 스크롤(가로 목록 안의 스크롤 등)은 무시한다.
  bool onScroll(ScrollNotification n, {Axis axis = Axis.vertical, double threshold = 400}) {
    if (n.metrics.axis == axis && n.metrics.extentAfter < threshold && !_loadMoreFailed) loadMore();
    return false;
  }

  void clear() {
    _generation++;
    _items = const [];
    _total = null;
    _hasMore = false;
    _isLoadingMore = false;
    _loadMoreFailed = false;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
