import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/features/playlists/domain/playlist_model.dart';
import 'package:streampulse/features/playlists/presentation/widgets/playlist_tile.dart';
import 'package:streampulse/app/theme.dart';

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
      trackCount: tracks.length,
      createdAt: DateTime(2026),
    );

TrackModel _track(String id) =>
    TrackModel(id: id, title: 'Track $id', url: 'u', duration: 60, position: 0);

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(theme: AppTheme.darkTheme, home: Scaffold(body: child)));

void main() {
  testWidgets('affiche le nom et "0 titre" pour une playlist vide et privee', (tester) async {
    await _pump(tester, PlaylistTile(playlist: _playlist(name: 'Empty')));

    expect(find.text('Empty'), findsOneWidget);
    expect(find.text('0 titres'), findsOneWidget);
  });

  testWidgets('accorde "titre" au singulier pour une seule piste', (tester) async {
    await _pump(tester, PlaylistTile(playlist: _playlist(tracks: [_track('t1')])));

    expect(find.text('1 titre'), findsOneWidget);
  });

  testWidgets('ajoute le suffixe Public pour une playlist publique', (tester) async {
    await _pump(tester, PlaylistTile(playlist: _playlist(isPublic: true, tracks: [_track('t1')])));

    expect(find.text('1 titre • Public'), findsOneWidget);
  });

  testWidgets('affiche un chevron sans callback proprietaire', (tester) async {
    await _pump(tester, PlaylistTile(playlist: _playlist()));

    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsNothing);
  });

  testWidgets('le menu declenche onDelete quand on choisit Supprimer',
      (tester) async {
    var deleted = false;
    await _pump(tester,
        PlaylistTile(playlist: _playlist(), onDelete: () => deleted = true));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    expect(deleted, isTrue);
  });

  testWidgets('le menu declenche onRename quand on choisit Renommer',
      (tester) async {
    var renamed = false;
    await _pump(tester,
        PlaylistTile(playlist: _playlist(), onRename: () => renamed = true));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Renommer'));
    expect(renamed, isTrue);
  });

  testWidgets('declenche onTap au tap sur la tuile', (tester) async {
    var tapped = false;
    await _pump(tester, PlaylistTile(playlist: _playlist(), onTap: () => tapped = true));

    await tester.tap(find.byType(ListTile));
    expect(tapped, isTrue);
  });
}
