import 'dart:math';
import '../../tidal_api/domain/models/media_item.dart';

enum PlaybackRepeatMode { off, all, one }

/// 재생 대기열. 플랫폼에 의존하지 않는 순수 로직이라 단위 테스트로 검증한다.
///
/// [tracks]는 실제 재생 순서(셔플 중이면 섞인 순서)이고, 원래 순서는 따로 보관해
/// 셔플을 끄면 현재 곡을 유지한 채 원래 순서로 돌아간다.
class PlayQueue {
  PlayQueue({Random? random}) : _random = random ?? Random();

  final Random _random;
  List<MediaTrack> _original = [];
  List<MediaTrack> _order = [];
  int _index = -1;
  bool _shuffle = false;
  PlaybackRepeatMode repeatMode = PlaybackRepeatMode.off;

  List<MediaTrack> get tracks => List.unmodifiable(_order);
  int get index => _index;
  bool get shuffle => _shuffle;
  bool get isEmpty => _order.isEmpty;
  MediaTrack? get current => (_index >= 0 && _index < _order.length) ? _order[_index] : null;
  bool get isAtEnd => _index >= _order.length - 1;

  /// 새 목록으로 대기열을 바꾸고 [startIndex]의 곡(원래 순서 기준)을 현재 곡으로 한다.
  void setTracks(List<MediaTrack> tracks, {int startIndex = 0}) {
    _original = List.of(tracks);
    if (_original.isEmpty) {
      _order = [];
      _index = -1;
      return;
    }
    final start = startIndex.clamp(0, _original.length - 1);
    if (_shuffle) {
      _order = _shuffledWithFirst(_original[start]);
      _index = 0;
    } else {
      _order = List.of(_original);
      _index = start;
    }
  }

  /// 곡 하나만 있는 대기열로 바꾼다.
  void setSingle(MediaTrack track) => setTracks([track]);

  /// 재생 순서 기준 [index]로 이동한다. 셔플 중이어도 순서를 다시 섞지 않는다.
  MediaTrack? jumpTo(int index) {
    if (index < 0 || index >= _order.length) return null;
    _index = index;
    return current;
  }

  /// 현재 대기열에서 [trackId]를 찾아 이동한다. 없으면 null.
  MediaTrack? jumpToTrack(String trackId) {
    final i = _order.indexWhere((t) => t.id == trackId);
    return i == -1 ? null : jumpTo(i);
  }

  /// 다음 곡. [auto]는 곡이 끝나서 넘어가는 경우로, 한 곡 반복이면 같은 곡을 돌려준다.
  /// 더 재생할 곡이 없으면 null.
  MediaTrack? next({bool auto = false}) {
    if (_order.isEmpty) return null;
    if (auto && repeatMode == PlaybackRepeatMode.one) return current;
    if (_index < _order.length - 1) {
      _index++;
      return current;
    }
    if (repeatMode == PlaybackRepeatMode.all) {
      _index = 0;
      return current;
    }
    return null;
  }

  /// 곡이 끝났을 때 이어서 재생될 곡을 미리 본다(대기열은 바꾸지 않는다).
  /// 한 곡 반복이면 null — 같은 곡 반복은 미리 등록하지 않고 끝난 뒤 다시 재생한다.
  MediaTrack? peekNext() {
    if (_order.isEmpty || repeatMode == PlaybackRepeatMode.one) return null;
    if (_index < _order.length - 1) return _order[_index + 1];
    if (repeatMode == PlaybackRepeatMode.all) return _order.first;
    return null;
  }

  /// 이전 곡. 처음이면 전체 반복일 때만 마지막 곡으로 간다.
  MediaTrack? previous() {
    if (_order.isEmpty) return null;
    if (_index > 0) {
      _index--;
      return current;
    }
    if (repeatMode == PlaybackRepeatMode.all) {
      _index = _order.length - 1;
      return current;
    }
    return null;
  }

  /// 대기열 끝에 곡을 덧붙인다(이미 있는 곡은 제외). 추가된 곡 수를 돌려준다.
  int append(List<MediaTrack> tracks) {
    final existing = _original.map((t) => t.id).toSet();
    final fresh = tracks.where((t) => existing.add(t.id)).toList();
    _original.addAll(fresh);
    _order.addAll(fresh);
    if (_index == -1 && _order.isNotEmpty) _index = 0;
    return fresh.length;
  }

  void setShuffle(bool enabled) {
    if (enabled == _shuffle) return;
    _shuffle = enabled;
    final now = current;
    if (enabled) {
      if (now != null) {
        _order = _shuffledWithFirst(now);
        _index = 0;
      } else {
        _order = List.of(_original)..shuffle(_random);
      }
    } else {
      _order = List.of(_original);
      _index = now == null ? (_order.isEmpty ? -1 : 0) : _order.indexWhere((t) => t.id == now.id);
    }
  }

  PlaybackRepeatMode cycleRepeat() {
    repeatMode = switch (repeatMode) {
      PlaybackRepeatMode.off => PlaybackRepeatMode.all,
      PlaybackRepeatMode.all => PlaybackRepeatMode.one,
      PlaybackRepeatMode.one => PlaybackRepeatMode.off,
    };
    return repeatMode;
  }

  List<MediaTrack> _shuffledWithFirst(MediaTrack first) {
    final rest = _original.where((t) => t.id != first.id).toList()..shuffle(_random);
    return [first, ...rest];
  }
}
