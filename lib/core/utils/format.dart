/// 초를 m:ss 형식으로 바꾼다. 예: 215 -> 3:35
String formatDuration(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final m = safe ~/ 60;
  final s = (safe % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
