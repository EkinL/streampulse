import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:streampulse/app/theme.dart';
import 'package:streampulse/core/network/api_endpoints.dart';
import 'package:streampulse/features/admin/presentation/providers/admin_feedback_provider.dart';
import 'package:streampulse/features/admin/presentation/screens/admin_feedback_screen.dart';

class _MockDio extends Mock implements Dio {}

Response<T> _response<T>(T data, {int statusCode = 200}) => Response<T>(
      requestOptions: RequestOptions(path: ''),
      statusCode: statusCode,
      data: data,
    );

DioException _errorResponse(int statusCode) => DioException(
      requestOptions: RequestOptions(path: ''),
      response: Response(
        requestOptions: RequestOptions(path: ''),
        statusCode: statusCode,
      ),
    );

Map<String, dynamic> _feedbackJson(String id, {String type = 'bug', String status = 'new'}) => {
      'id': id,
      'user_id': 'u1',
      'type': type,
      'message': 'Le lecteur plante au demarrage',
      'app_version': '1.0.0',
      'platform': 'android',
      'status': status,
      'created_at': '2026-09-02T10:00:00Z',
      'updated_at': '2026-09-02T10:00:00Z',
    };

Future<void> _pump(WidgetTester tester, {required _MockDio dio}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [adminFeedbackProvider.overrideWith((ref) => AdminFeedbackNotifier(dio))],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(body: AdminFeedbackScreen()),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  late _MockDio dio;

  setUp(() {
    dio = _MockDio();
  });

  testWidgets('affiche "No reports found." pour une liste vide', (tester) async {
    when(() => dio.get(ApiEndpoints.adminFeedback, queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => _response({'data': <dynamic>[]}));

    await _pump(tester, dio: dio);
    await tester.pump();

    expect(find.text('No reports found.'), findsOneWidget);
  });

  testWidgets('affiche une erreur et permet de reessayer', (tester) async {
    when(() => dio.get(ApiEndpoints.adminFeedback, queryParameters: any(named: 'queryParameters')))
        .thenThrow(_errorResponse(500));

    await _pump(tester, dio: dio);
    await tester.pump();

    expect(find.textContaining('Error:'), findsOneWidget);

    when(() => dio.get(ApiEndpoints.adminFeedback, queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => _response({
              'data': [_feedbackJson('f1')],
            }));
    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(find.textContaining('Le lecteur plante'), findsOneWidget);
  });

  testWidgets('liste les signalements avec leur type et leur statut', (tester) async {
    when(() => dio.get(ApiEndpoints.adminFeedback, queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => _response({
              'data': [_feedbackJson('f1', type: 'suggestion', status: 'in_progress')],
            }));

    await _pump(tester, dio: dio);
    await tester.pump();

    expect(find.text('Suggestion'), findsOneWidget);
    expect(find.text('EN COURS'), findsOneWidget);
    expect(find.textContaining('Le lecteur plante'), findsOneWidget);
  });

  testWidgets('un filtre de statut relance la recherche avec ce statut', (tester) async {
    when(() => dio.get(ApiEndpoints.adminFeedback, queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => _response({
              'data': [_feedbackJson('f1')],
            }));
    await _pump(tester, dio: dio);
    await tester.pump();

    when(() => dio.get(ApiEndpoints.adminFeedback, queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => _response({'data': <dynamic>[]}));

    await tester.tap(find.text('Résolu'));
    await tester.pump();
    await tester.pump();

    final captured = verify(() => dio.get(ApiEndpoints.adminFeedback, queryParameters: captureAny(named: 'queryParameters')))
        .captured
        .last as Map<String, dynamic>;
    expect(captured['status'], 'resolved');
    expect(find.text('No reports found.'), findsOneWidget);
  });

  testWidgets('changer le statut appelle updateStatus et rafraichit', (tester) async {
    when(() => dio.get(ApiEndpoints.adminFeedback, queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => _response({
              'data': [_feedbackJson('f1', status: 'new')],
            }));
    await _pump(tester, dio: dio);
    await tester.pump();

    when(() => dio.put(ApiEndpoints.adminFeedbackStatus('f1'), data: {'status': 'resolved'}))
        .thenAnswer((_) async => _response(null));
    when(() => dio.get(ApiEndpoints.adminFeedback, queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => _response({
              'data': [_feedbackJson('f1', status: 'resolved')],
            }));

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Résolu').last);
    await tester.pumpAndSettle();

    verify(() => dio.put(ApiEndpoints.adminFeedbackStatus('f1'), data: {'status': 'resolved'})).called(1);
    expect(find.textContaining('marqué Résolu'), findsOneWidget);
  });

  testWidgets('un echec de changement de statut affiche une erreur', (tester) async {
    when(() => dio.get(ApiEndpoints.adminFeedback, queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => _response({
              'data': [_feedbackJson('f1', status: 'new')],
            }));
    await _pump(tester, dio: dio);
    await tester.pump();

    when(() => dio.put(ApiEndpoints.adminFeedbackStatus('f1'), data: {'status': 'resolved'}))
        .thenThrow(_errorResponse(403));

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Résolu').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Échec de la mise à jour'), findsOneWidget);
  });
}
