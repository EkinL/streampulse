import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/features/streams/domain/stream_model.dart';
import 'package:streampulse/features/streams/presentation/widgets/stream_card.dart';
import 'package:streampulse/app/theme.dart';

StreamModel _stream({
  String title = 'My Stream',
  String description = '',
  String status = 'live',
  int listenerCount = 0,
  String format = 'mp3',
}) =>
    StreamModel(
      id: 's1',
      title: title,
      description: description,
      ownerId: 'u1',
      status: status,
      listenerCount: listenerCount,
      format: format,
      createdAt: DateTime(2026),
    );

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(theme: AppTheme.darkTheme, home: Scaffold(body: child)));

void main() {
  testWidgets('affiche le titre, le format et le badge LIVE pour un stream en direct',
      (tester) async {
    await _pump(
      tester,
      StreamCard(stream: _stream(title: 'Night Show', format: 'aac', status: 'live')),
    );

    expect(find.text('Night Show'), findsOneWidget);
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('AAC'), findsOneWidget);
  });

  testWidgets('affiche HORS LIGNE et masque le compteur d\'auditeurs quand le stream est hors ligne',
      (tester) async {
    await _pump(tester, StreamCard(stream: _stream(status: 'ended', listenerCount: 42)));

    expect(find.text('HORS LIGNE'), findsOneWidget);
    expect(find.text('42'), findsNothing);
  });

  testWidgets('formate les auditeurs en K au-dela de 1000', (tester) async {
    await _pump(tester, StreamCard(stream: _stream(status: 'live', listenerCount: 1500)));

    expect(find.text('1.5K'), findsOneWidget);
  });

  testWidgets('affiche la description quand elle est presente', (tester) async {
    await _pump(tester, StreamCard(stream: _stream(description: 'A cozy late night mix')));

    expect(find.text('A cozy late night mix'), findsOneWidget);
  });

  testWidgets('n\'affiche pas d\'icone edit sans callback onEdit', (tester) async {
    await _pump(tester, StreamCard(stream: _stream()));

    expect(find.byIcon(Icons.edit), findsNothing);
  });

  testWidgets('affiche l\'icone edit et la declenche quand onEdit est fourni', (tester) async {
    var edited = false;
    await _pump(
      tester,
      StreamCard(stream: _stream(), onEdit: () => edited = true),
    );

    await tester.tap(find.byIcon(Icons.edit));
    expect(edited, isTrue);
  });

  testWidgets('declenche onFavorite au tap sur le coeur', (tester) async {
    var favorited = false;
    await _pump(
      tester,
      StreamCard(stream: _stream(), onFavorite: () => favorited = true),
    );

    await tester.tap(find.byIcon(Icons.favorite_border));
    expect(favorited, isTrue);
  });

  testWidgets('declenche onTap au tap sur la carte', (tester) async {
    var tapped = false;
    await _pump(tester, StreamCard(stream: _stream(), onTap: () => tapped = true));

    await tester.tap(find.byType(StreamCard));
    expect(tapped, isTrue);
  });
}
