import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:streampulse/core/network/api_endpoints.dart';
import 'package:streampulse/features/admin/presentation/providers/admin_feedback_provider.dart';

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

Map<String, dynamic> _feedbackJson(String id, {String status = 'new'}) => {
      'id': id,
      'user_id': 'u1',
      'type': 'bug',
      'message': 'Le lecteur plante',
      'app_version': '1.0.0',
      'platform': 'android',
      'status': status,
      'created_at': '2026-09-02T10:00:00Z',
      'updated_at': '2026-09-02T10:00:00Z',
    };

void main() {
  late _MockDio dio;

  setUp(() {
    dio = _MockDio();
  });

  test('fetchFeedback est declenche a la creation et parse la liste', () async {
    when(() => dio.get(ApiEndpoints.adminFeedback, queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => _response({
              'data': [_feedbackJson('f1'), _feedbackJson('f2')],
            }));

    final notifier = AdminFeedbackNotifier(dio);
    await Future<void>.delayed(Duration.zero);

    final state = notifier.state;
    expect(state.hasValue, isTrue);
    expect(state.value, hasLength(2));
    expect(state.value!.map((f) => f.id), ['f1', 'f2']);
  });

  test('fetchFeedback passe par un etat loading puis data', () async {
    when(() => dio.get(ApiEndpoints.adminFeedback, queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => _response({'data': <dynamic>[]}));
    final notifier = AdminFeedbackNotifier(dio);

    expect(notifier.state.isLoading, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(notifier.state.hasValue, isTrue);
  });

  test('fetchFeedback transmet le filtre de statut en query', () async {
    when(() => dio.get(ApiEndpoints.adminFeedback, queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => _response({'data': <dynamic>[]}));
    final notifier = AdminFeedbackNotifier(dio);
    await Future<void>.delayed(Duration.zero);

    await notifier.fetchFeedback(status: 'resolved');

    final captured = verify(() => dio.get(ApiEndpoints.adminFeedback, queryParameters: captureAny(named: 'queryParameters')))
        .captured
        .last as Map<String, dynamic>;
    expect(captured['status'], 'resolved');
  });

  test('fetchFeedback en erreur reseau : etat error', () async {
    when(() => dio.get(ApiEndpoints.adminFeedback, queryParameters: any(named: 'queryParameters')))
        .thenThrow(_errorResponse(500));

    final notifier = AdminFeedbackNotifier(dio);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state.hasError, isTrue);
  });

  test('updateStatus envoie le nouveau statut puis rafraichit avec le meme filtre', () async {
    when(() => dio.get(ApiEndpoints.adminFeedback, queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => _response({
              'data': [_feedbackJson('f1', status: 'new')],
            }));
    when(() => dio.put(ApiEndpoints.adminFeedbackStatus('f1'), data: {'status': 'resolved'}))
        .thenAnswer((_) async => _response(null));

    final notifier = AdminFeedbackNotifier(dio);
    await Future<void>.delayed(Duration.zero);
    await notifier.fetchFeedback(status: 'new');

    await notifier.updateStatus(id: 'f1', status: 'resolved');

    verify(() => dio.put(ApiEndpoints.adminFeedbackStatus('f1'), data: {'status': 'resolved'})).called(1);
    final captured = verify(() => dio.get(ApiEndpoints.adminFeedback, queryParameters: captureAny(named: 'queryParameters')))
        .captured
        .last as Map<String, dynamic>;
    expect(captured['status'], 'new');
  });

  test('updateStatus propage une ApiException en cas d\'echec', () async {
    when(() => dio.get(ApiEndpoints.adminFeedback, queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => _response({'data': <dynamic>[]}));
    when(() => dio.put(ApiEndpoints.adminFeedbackStatus('f1'), data: any(named: 'data')))
        .thenThrow(_errorResponse(403));

    final notifier = AdminFeedbackNotifier(dio);
    await Future<void>.delayed(Duration.zero);

    await expectLater(
      () => notifier.updateStatus(id: 'f1', status: 'resolved'),
      throwsA(isA<Exception>()),
    );
  });
}
