import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/features/playlists/domain/playlist_model.dart';
import 'package:streampulse/features/playlists/presentation/widgets/playlist_tile.dart';

PlaylistModel _playlist({
  String name = 'My playlist',
  bool isPublic = false,
  List<TrackModel> tracks = const [],
}) =>
    PlaylistModel(
      id: 'p1',
      name: name,
      ownerId: 'u1',
      isPublic: isPublic,
      tracks: tracks,
      createdAt: DateTime(2026),
    );

TrackModel _track(String id) =>
    TrackModel(id: id, title: 'Track $id', url: 'u', duration: 60, position: 0);

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

void main() {
  testWidgets('affiche le nom et "0 track" pour une playlist vide et privee', (tester) async {
    await _pump(tester, PlaylistTile(playlist: _playlist(name: 'Empty')));

    expect(find.text('Empty'), findsOneWidget);
    expect(find.text('0 tracks'), findsOneWidget);
  });

  testWidgets('accorde "track" au singulier pour une seule piste', (tester) async {
    await _pump(tester, PlaylistTile(playlist: _playlist(tracks: [_track('t1')])));

    expect(find.text('1 track'), findsOneWidget);
  });

  testWidgets('ajoute le suffixe Public pour une playlist publique', (tester) async {
    await _pump(tester, PlaylistTile(playlist: _playlist(isPublic: true, tracks: [_track('t1')])));

    expect(find.text('1 track • Public'), findsOneWidget);
  });

  testWidgets('affiche un chevron sans callback onDelete', (tester) async {
    await _pump(tester, PlaylistTile(playlist: _playlist()));

    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });

  testWidgets('affiche un bouton delete et le declenche quand onDelete est fourni',
      (tester) async {
    var deleted = false;
    await _pump(tester, PlaylistTile(playlist: _playlist(), onDelete: () => deleted = true));

    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    await tester.tap(find.byIcon(Icons.delete_outline));
    expect(deleted, isTrue);
  });

  testWidgets('declenche onTap au tap sur la tuile', (tester) async {
    var tapped = false;
    await _pump(tester, PlaylistTile(playlist: _playlist(), onTap: () => tapped = true));

    await tester.tap(find.byType(ListTile));
    expect(tapped, isTrue);
  });
}
