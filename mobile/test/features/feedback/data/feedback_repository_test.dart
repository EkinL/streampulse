import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:streampulse/core/network/api_endpoints.dart';
import 'package:streampulse/core/network/api_exceptions.dart';
import 'package:streampulse/features/feedback/data/feedback_repository.dart';
import 'package:streampulse/features/feedback/domain/feedback_type.dart';

class _MockDio extends Mock implements Dio {}

Response<T> _response<T>(T data, {int statusCode = 201}) => Response<T>(
      requestOptions: RequestOptions(path: ''),
      statusCode: statusCode,
      data: data,
    );

DioException _errorResponse(int statusCode, {String? message}) => DioException(
      requestOptions: RequestOptions(path: ''),
      response: Response(
        requestOptions: RequestOptions(path: ''),
        statusCode: statusCode,
        data: message == null
            ? null
            : {
                'error': {'code': 'BAD_REQUEST', 'message': message},
              },
      ),
    );

void main() {
  late _MockDio dio;
  late FeedbackRepository repository;

  setUp(() {
    dio = _MockDio();
    repository = FeedbackRepository(dio);
  });

  group('submitFeedback', () {
    test('envoie le type, le message, la version et la plateforme', () async {
      when(() => dio.post(ApiEndpoints.feedback, data: any(named: 'data')))
          .thenAnswer((_) async => _response(null));

      await repository.submitFeedback(
        type: FeedbackType.bug,
        message: 'Le lecteur coupe le son.',
        appVersion: '1.0.0',
        platform: 'android',
      );

      final captured = verify(() => dio.post(ApiEndpoints.feedback, data: captureAny(named: 'data')))
          .captured
          .single as Map<String, dynamic>;
      expect(captured['type'], 'bug');
      expect(captured['message'], 'Le lecteur coupe le son.');
      expect(captured['app_version'], '1.0.0');
      expect(captured['platform'], 'android');
    });

    test('omet app_version quand il est absent', () async {
      when(() => dio.post(ApiEndpoints.feedback, data: any(named: 'data')))
          .thenAnswer((_) async => _response(null));

      await repository.submitFeedback(type: FeedbackType.suggestion, message: 'Idée sympa');

      final captured = verify(() => dio.post(ApiEndpoints.feedback, data: captureAny(named: 'data')))
          .captured
          .single as Map<String, dynamic>;
      expect(captured.containsKey('app_version'), isFalse);
      // La plateforme, elle, est toujours deduite (dart:io Platform), meme
      // sans version d'app.
      expect(captured['platform'], isNotNull);
    });

    test('propage une ApiException avec le message serveur', () async {
      when(() => dio.post(ApiEndpoints.feedback, data: any(named: 'data')))
          .thenThrow(_errorResponse(400, message: 'message is required'));

      expect(
        () => repository.submitFeedback(type: FeedbackType.bug, message: ''),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'message is required')),
      );
    });
  });
}
