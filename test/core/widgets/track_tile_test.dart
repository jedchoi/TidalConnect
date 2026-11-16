import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tidal_connect_lite/core/providers.dart';
import 'package:tidal_connect_lite/core/widgets/track_tile.dart';
import 'package:tidal_connect_lite/features/player/data/player_manager.dart';
import 'package:tidal_connect_lite/features/tidal_api/domain/models/media_item.dart';

MediaTrack track(String id, {String quality = 'LOSSLESS'}) => MediaTrack(
      id: id,
      title: 'Track $id',
      artistName: 'Artist',
      albumTitle: 'Album',
      coverUrl: '',
      durationSeconds: 125,
      audioQuality: quality,
    );

/// 재생 요청만 기록하는 PlayerManager.
class SpyPlayer extends PlayerManager {
  SpyPlayer() : super.forTesting();

  final List<(String, int?)> played = [];
  int toggles = 0;

  @override
  Future<bool> playTrack(MediaTrack track, {List<MediaTrack>? queue, int? index}) async {
    played.add((track.id, index));
    return true;
  }

  @override
  void togglePlayPause() => toggles++;
}

void main() {
  late SpyPlayer player;
  final queue = [track('1'), track('2', quality: 'HI_RES_LOSSLESS')];

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(ProviderScope(
        overrides: [playerManagerProvider.overrideWithValue(player)],
        child: MaterialApp(home: Scaffold(body: child)),
      ));

  setUp(() => player = SpyPlayer());

  testWidgets('제목·부제·음질 배지·길이를 보여준다', (tester) async {
    await pump(tester, TrackTile(track: queue[1], queue: queue, index: 1, showDuration: true));

    expect(find.text('Track 2'), findsOneWidget);
    expect(find.text('Artist • Album'), findsOneWidget);
    expect(find.text('MAX'), findsOneWidget);
    expect(find.text('2:05'), findsOneWidget);
  });

  testWidgets('누르면 대기열과 위치를 넘겨 재생하고 onPlay를 부른다', (tester) async {
    var onPlayCount = 0;
    await pump(tester, TrackTile(track: queue[1], queue: queue, index: 1, onPlay: () => onPlayCount++));

    await tester.tap(find.byType(ListTile));
    expect(player.played, [('2', 1)]);
    expect(onPlayCount, 1);
  });

  testWidgets('현재 곡이면 강조하고 버튼이 재생/일시정지를 전환한다', (tester) async {
    player.currentTrackNotifier.value = queue[0];
    player.isPlayingNotifier.value = true;
    await pump(tester, TrackTile(track: queue[0], queue: queue, index: 0));

    expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);
    await tester.tap(find.byIcon(Icons.pause_circle_filled));
    expect(player.toggles, 1);
    expect(player.played, isEmpty);

    player.isPlayingNotifier.value = false;
    await tester.pump();
    expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
  });
}
