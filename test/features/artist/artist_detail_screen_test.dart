import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tidal_connect_lite/features/artist/presentation/artist_detail_screen.dart';
import 'package:tidal_connect_lite/features/tidal_api/domain/models/media_item.dart';

import '../../helpers/app_overrides.dart';

void main() {
  testWidgets('아티스트 화면은 인기 트랙과 앨범을 보여준다', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final app = TestApp();
    app.api.tracks = [
      MediaTrack(id: 't1', title: 'Hit Song', artistName: 'Band', albumTitle: 'X', coverUrl: '', durationSeconds: 200),
    ];
    app.api.artistAlbums = [
      MediaAlbum(id: 'a1', title: 'First Album', artistName: 'Band', coverUrl: '', numberOfTracks: 10),
    ];

    await tester.pumpWidget(ProviderScope(
      overrides: app.overrides,
      child: MaterialApp(home: ArtistDetailScreen(artist: MediaArtist(id: '7', name: 'Band', pictureUrl: ''))),
    ));
    await tester.pump();

    expect(app.api.calls, containsAll(['getArtistTopTracks:7', 'getArtistAlbums:7:0']));
    expect(find.text('인기 트랙'), findsOneWidget);
    expect(find.text('Hit Song'), findsOneWidget);
    expect(find.text('First Album'), findsOneWidget);
  });
}
