import 'package:flutter/foundation.dart';

enum LogType { info, success, warning, error, network }

class LogEntry {
  final DateTime timestamp;
  final String tag;
  final String message;
  final LogType type;

  LogEntry({
    required this.timestamp,
    required this.tag,
    required this.message,
    this.type = LogType.info,
  });

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }
}

/// 로그에 남겨도 되는 형태로 URL을 줄인다. 쿼리 문자열(서명, 토큰)과 경로 끝의 토큰을 지운다.
String maskUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return '<url>';
  return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}/…';
}

class AppLogger {
  static final ValueNotifier<List<LogEntry>> logsNotifier = ValueNotifier<List<LogEntry>>([]);
  static final List<LogEntry> _logs = [];

  static void log(String tag, String message, {LogType type = LogType.info}) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      tag: tag,
      message: message,
      type: type,
    );
    _logs.insert(0, entry);
    if (_logs.length > 200) {
      _logs.removeLast();
    }
    logsNotifier.value = List.unmodifiable(_logs);
    if (kDebugMode) {
      debugPrint('[${entry.formattedTime}] [$tag] $message');
    }
  }

  static void clear() {
    _logs.clear();
    logsNotifier.value = [];
  }
}
