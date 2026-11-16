import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 최근 검색어를 저장한다. 민감 정보가 아니므로 shared_preferences에 둔다.
class SearchHistoryStore {
  SearchHistoryStore({FlutterSecureStorage? legacyStorage})
      : _legacyStorage = legacyStorage ?? const FlutterSecureStorage();

  static const String key = 'search_history';
  static const String _legacyKey = 'search_history_list';
  static const int maxItems = 15;

  final FlutterSecureStorage _legacyStorage;

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<List<String>> load() async {
    final stored = (await _prefs).getStringList(key);
    if (stored != null) return stored;
    return _migrateLegacy();
  }

  /// [query]를 맨 앞에 두고 중복을 없앤 새 목록을 저장하고 돌려준다.
  Future<List<String>> add(List<String> current, String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return current;
    final next = addToHistory(current, trimmed);
    await (await _prefs).setStringList(key, next);
    return next;
  }

  Future<List<String>> remove(List<String> current, String query) async {
    final next = [...current]..remove(query);
    await (await _prefs).setStringList(key, next);
    return next;
  }

  Future<void> clear() async {
    await (await _prefs).remove(key);
  }

  static List<String> addToHistory(List<String> current, String query) {
    final next = [query, ...current.where((e) => e != query)];
    return next.length > maxItems ? next.sublist(0, maxItems) : next;
  }

  /// 예전 버전은 보안 저장소에 JSON 문자열로 저장했다. 한 번 옮기고 지운다.
  Future<List<String>> _migrateLegacy() async {
    try {
      final jsonStr = await _legacyStorage.read(key: _legacyKey);
      if (jsonStr == null || jsonStr.isEmpty) return const [];
      final list = (jsonDecode(jsonStr) as List).map((e) => e.toString()).toList();
      await (await _prefs).setStringList(key, list);
      await _legacyStorage.delete(key: _legacyKey);
      return list;
    } catch (_) {
      return const [];
    }
  }
}
