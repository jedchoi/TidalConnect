import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:tidal_connect_lite/features/player/domain/play_queue.dart';
import 'package:tidal_connect_lite/features/tidal_api/domain/models/media_item.dart';

MediaTrack t(String id) => MediaTrack(
      id: id,
      title: 'Track $id',
      artistName: 'Artist',
      albumTitle: 'Album',
      coverUrl: '',
      durationSeconds: 180,
    );

List<String> ids(PlayQueue q) => q.tracks.map((e) => e.id).toList();

void main() {
  final five = ['1', '2', '3', '4', '5'].map(t).toList();

  test('setTracks starts at the requested index', () {
    final q = PlayQueue()..setTracks(five, startIndex: 2);
    expect(q.current!.id, '3');
    expect(ids(q), ['1', '2', '3', '4', '5']);
  });

  test('shuffle keeps the current track first and restores the original order when turned off', () {
    final q = PlayQueue(random: Random(1))..setTracks(five, startIndex: 2);
    q.setShuffle(true);
    expect(q.current!.id, '3');
    expect(q.index, 0);
    expect(ids(q).toSet(), {'1', '2', '3', '4', '5'});

    q.next();
    final playing = q.current!.id;
    q.setShuffle(false);
    expect(ids(q), ['1', '2', '3', '4', '5']);
    expect(q.current!.id, playing);
  });

  test('jumpTo during shuffle does not reshuffle', () {
    final q = PlayQueue(random: Random(7))..setTracks(five);
    q.setShuffle(true);
    final before = ids(q);
    q.jumpTo(3);
    expect(ids(q), before);
    expect(q.current!.id, before[3]);
    q.setShuffle(false);
    expect(ids(q), ['1', '2', '3', '4', '5']);
  });

  test('repeat off stops at the end', () {
    final q = PlayQueue()..setTracks(five, startIndex: 4);
    expect(q.next(auto: true), isNull);
    expect(q.current!.id, '5');
  });

  test('repeat all wraps around in both directions', () {
    final q = PlayQueue()
      ..setTracks(five, startIndex: 4)
      ..repeatMode = PlaybackRepeatMode.all;
    expect(q.next()!.id, '1');
    expect(q.previous()!.id, '5');
  });

  test('repeat one replays the same track only when a track ends', () {
    final q = PlayQueue()
      ..setTracks(five, startIndex: 1)
      ..repeatMode = PlaybackRepeatMode.one;
    expect(q.next(auto: true)!.id, '2');
    expect(q.next()!.id, '3');
  });

  test('append skips tracks already in the queue', () {
    final q = PlayQueue()..setTracks(five.take(2).toList());
    final added = q.append([t('2'), t('6'), t('7')]);
    expect(added, 2);
    expect(ids(q), ['1', '2', '6', '7']);
  });

  test('cycleRepeat goes off -> all -> one -> off', () {
    final q = PlayQueue();
    expect(q.cycleRepeat(), PlaybackRepeatMode.all);
    expect(q.cycleRepeat(), PlaybackRepeatMode.one);
    expect(q.cycleRepeat(), PlaybackRepeatMode.off);
  });
}
