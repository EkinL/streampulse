import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:streampulse/features/music/domain/music_model.dart';
import 'package:streampulse/features/music/presentation/providers/music_favorites_provider.dart';
import 'package:streampulse/features/music/presentation/widgets/music_tile.dart';
import 'package:streampulse/app/theme.dart';

class _MockDio extends Mock implements Dio {}

MusicModel _music({
  String title = 'Track title',
  String artist = 'Artist',
  int duration = 65,
}) =>
    MusicModel(
      id: 'm1',
      title: title,
      artist: artist,
      album: '',
      duration: duration,
      url: 'https://cdn/m1.mp3',
      uploadedBy: 'u1',
      createdAt: DateTime(2026),
    );

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Set<String> favorites = const {},
  Dio? dio,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        musicFavoritesProvider.overrideWith(
          (ref) => MusicFavoritesNotifier(dio ?? _MockDio())..state = favorites,
        ),
      ],
      child: MaterialApp(theme: AppTheme.darkTheme, home: Scaffold(body: child)),
    ),
  );
}

void main() {
  testWidgets('affiche le titre, l\'artiste et la duree formatee', (tester) async {
    await _pump(tester, MusicTile(music: _music(title: 'Around the World', duration: 65)));

    expect(find.text('Around the World'), findsOneWidget);
    expect(find.text('Artist'), findsOneWidget);
    expect(find.text('1:05'), findsOneWidget);
  });

  testWidgets('affiche "Unknown artist" quand l\'artiste est vide', (tester) async {
    await _pump(tester, MusicTile(music: _music(artist: '')));

    expect(find.text('Unknown artist'), findsOneWidget);
  });

  testWidgets('coeur plein quand le morceau est deja favori', (tester) async {
    await _pump(tester, MusicTile(music: _music()), favorites: {'m1'});

    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsNothing);
  });

  testWidgets('coeur vide quand le morceau n\'est pas favori', (tester) async {
    await _pump(tester, MusicTile(music: _music()));

    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
  });

  testWidgets('n\'affiche pas d\'icone edit sans callback', (tester) async {
    await _pump(tester, MusicTile(music: _music()));

    expect(find.byIcon(Icons.edit), findsNothing);
  });

  testWidgets('affiche l\'icone edit et la declenche quand onEdit est fourni', (tester) async {
    var edited = false;
    await _pump(tester, MusicTile(music: _music(), onEdit: () => edited = true));

    await tester.tap(find.byIcon(Icons.edit));
    expect(edited, isTrue);
  });

  testWidgets('declenche onTap au tap sur la tuile', (tester) async {
    var tapped = false;
    await _pump(tester, MusicTile(music: _music(), onTap: () => tapped = true));

    await tester.tap(find.byIcon(Icons.play_circle_filled));
    expect(tapped, isTrue);
  });

  testWidgets('ouvre le menu et propose "Add to playlist"', (tester) async {
    var added = false;
    await _pump(
      tester,
      MusicTile(music: _music(), onAddToPlaylist: () => added = true),
    );

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Add to playlist'), findsOneWidget);

    await tester.tap(find.text('Add to playlist'));
    await tester.pumpAndSettle();

    expect(added, isTrue);
  });
}
