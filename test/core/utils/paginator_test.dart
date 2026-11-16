import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tidal_connect_lite/core/utils/paginator.dart';
import 'package:tidal_connect_lite/features/tidal_api/data/tidal_api_client.dart';

void main() {
  /// 0..total-1 숫자를 pageSize씩 돌려주는 가짜 API.
  Paginator<int> numbers({int total = 5, int pageSize = 2, List<int>? requested, bool Function(int offset)? failAt}) {
    return Paginator<int>((offset) async {
      requested?.add(offset);
      if (failAt?.call(offset) ?? false) throw Exception('boom');
      final items = [for (var i = offset; i < offset + pageSize && i < total; i++) i];
      return PageResult(items: items, offset: offset, total: total, hasMore: offset + items.length < total);
    });
  }

  test('refresh는 첫 페이지를, loadMore는 이어지는 페이지를 받는다', () async {
    final requested = <int>[];
    final p = numbers(requested: requested);
    await p.refresh();
    expect(p.items, [0, 1]);
    expect(p.hasMore, isTrue);
    expect(p.totalCount, 5);

    await p.loadMore();
    await p.loadMore();
    expect(p.items, [0, 1, 2, 3, 4]);
    expect(p.hasMore, isFalse);

    await p.loadMore();
    expect(requested, [0, 2, 4]);
  });

  test('받는 중에 loadMore를 다시 불러도 요청은 한 번만 나간다', () async {
    final gate = Completer<void>();
    var calls = 0;
    final p = Paginator<int>((offset) async {
      calls++;
      if (offset > 0) await gate.future;
      return PageResult(items: [offset], offset: offset, hasMore: true);
    });
    await p.refresh();
    final a = p.loadMore();
    final b = p.loadMore();
    gate.complete();
    await Future.wait([a, b]);
    expect(calls, 2);
    expect(p.items, [0, 1]);
  });

  test('다음 페이지 실패는 표시만 하고 다시 부르면 재시도한다', () async {
    var fail = true;
    final p = numbers(failAt: (offset) => offset == 2 && fail);
    await p.refresh();
    await p.loadMore();
    expect(p.loadMoreFailed, isTrue);
    expect(p.items, [0, 1]);

    fail = false;
    await p.loadMore();
    expect(p.loadMoreFailed, isFalse);
    expect(p.items, [0, 1, 2, 3]);
  });

  test('refresh 이후에 도착한 이전 loadMore 결과는 버린다', () async {
    final gate = Completer<void>();
    final p = Paginator<int>((offset) async {
      if (offset > 0) await gate.future;
      return PageResult(items: [offset + 100], offset: offset, hasMore: true);
    });
    await p.refresh();
    final pending = p.loadMore();
    await p.refresh();
    gate.complete();
    await pending;
    expect(p.items, [100]);
  });
}
