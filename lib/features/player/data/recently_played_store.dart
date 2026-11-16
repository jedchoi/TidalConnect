import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../tidal_api/domain/models/media_item.dart';

/// 최근 재생한 곡을 기기에 최대 [maxItems]개까지 저장한다. 같은 곡은 맨 앞으로 옮긴다.
class RecentlyPlayedStore {
  static const String key = 'recently_played';
  static const int maxItems = 50;

  final ValueNotifier<List<MediaTrack>> tracks = ValueNotifier(const []);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List;
      tracks.value = List.unmodifiable(
        list.whereType<Map<String, dynamic>>().map(MediaTrack.fromJson).where((t) => t.id.isNotEmpty),
      );
    } catch (_) {
      tracks.value = const [];
    }
  }

  Future<void> add(MediaTrack track) async {
    if (track.id.isEmpty) return;
    final next = [track, ...tracks.value.where((t) => t.id != track.id)];
    tracks.value = List.unmodifiable(next.length > maxItems ? next.sublist(0, maxItems) : next);
    await _save();
  }

  Future<void> clear() async {
    tracks.value = const [];
    await _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(tracks.value.map((t) => t.toJson()).toList()));
    } catch (_) {}
  }
}
