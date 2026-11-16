import 'package:flutter_test/flutter_test.dart';
import 'package:tidal_connect_lite/features/search/data/search_history_store.dart';

void main() {
  group('SearchHistoryStore.addToHistory', () {
    test('새 검색어를 맨 앞에 넣는다', () {
      expect(SearchHistoryStore.addToHistory(['a', 'b'], 'c'), ['c', 'a', 'b']);
    });

    test('이미 있는 검색어는 맨 앞으로 옮기고 중복을 남기지 않는다', () {
      expect(SearchHistoryStore.addToHistory(['a', 'b', 'c'], 'b'), ['b', 'a', 'c']);
    });

    test('최대 개수를 넘으면 오래된 항목을 버린다', () {
      final full = List.generate(SearchHistoryStore.maxItems, (i) => 'q$i');
      final next = SearchHistoryStore.addToHistory(full, 'new');
      expect(next.length, SearchHistoryStore.maxItems);
      expect(next.first, 'new');
      expect(next.contains('q${SearchHistoryStore.maxItems - 1}'), isFalse);
    });
  });
}
