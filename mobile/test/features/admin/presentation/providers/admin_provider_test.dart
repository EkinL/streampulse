import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:streampulse/core/network/api_client.dart';
import 'package:streampulse/core/network/api_endpoints.dart';
import 'package:streampulse/features/admin/presentation/providers/admin_provider.dart';

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

Map<String, dynamic> _userJson(String id) => {
      'id': id,
      'email': '$id@example.com',
      'username': id,
      'role': 'listener',
    };

void main() {
  late _MockDio dio;

  setUp(() {
    dio = _MockDio();
  });

  test('adminProvider construit un AdminNotifier branche sur dioProvider', () async {
    when(() => dio.get(ApiEndpoints.adminUsers)).thenAnswer((_) async => _response({
          'data': [_userJson('u1')],
        }));
    final container = ProviderContainer(overrides: [dioProvider.overrideWithValue(dio)]);
    addTearDown(container.dispose);

    expect(container.read(adminProvider.notifier), isA<AdminNotifier>());
    await Future<void>.delayed(Duration.zero);
    expect(container.read(adminProvider).value, hasLength(1));
  });

  test('fetchUsers est declenche a la creation et parse la liste', () async {
    when(() => dio.get(ApiEndpoints.adminUsers)).thenAnswer((_) async => _response({
          'data': [_userJson('u1'), _userJson('u2')],
        }));

    final notifier = AdminNotifier(dio);
    await Future<void>.delayed(Duration.zero);

    final state = notifier.state;
    expect(state.hasValue, isTrue);
    expect(state.value, hasLength(2));
    expect(state.value!.map((u) => u.id), ['u1', 'u2']);
  });

  test('fetchUsers passe par un etat loading puis data', () async {
    when(() => dio.get(ApiEndpoints.adminUsers)).thenAnswer((_) async => _response({
          'data': <dynamic>[],
        }));
    final notifier = AdminNotifier(dio);

    expect(notifier.state.isLoading, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(notifier.state.hasValue, isTrue);
  });

  test('fetchUsers en erreur reseau : etat error avec le message traduit', () async {
    when(() => dio.get(ApiEndpoints.adminUsers)).thenThrow(_errorResponse(500));

    final notifier = AdminNotifier(dio);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state.hasError, isTrue);
  });

  test('updateRole envoie le nouveau role puis rafraichit la liste', () async {
    when(() => dio.get(ApiEndpoints.adminUsers)).thenAnswer((_) async => _response({
          'data': [_userJson('u1')],
        }));
    when(() => dio.put(
          ApiEndpoints.adminUserRole('u1'),
          data: {'role': 'admin'},
        )).thenAnswer((_) async => _response(null));

    final notifier = AdminNotifier(dio);
    await Future<void>.delayed(Duration.zero);

    await notifier.updateRole(userId: 'u1', role: 'admin');

    verify(() => dio.put(ApiEndpoints.adminUserRole('u1'), data: {'role': 'admin'})).called(1);
    verify(() => dio.get(ApiEndpoints.adminUsers)).called(2);
  });

  test('updateRole propage une ApiException en cas d\'echec', () async {
    when(() => dio.get(ApiEndpoints.adminUsers)).thenAnswer((_) async => _response({
          'data': <dynamic>[],
        }));
    when(() => dio.put(
          ApiEndpoints.adminUserRole('u1'),
          data: any(named: 'data'),
        )).thenThrow(_errorResponse(403));

    final notifier = AdminNotifier(dio);
    await Future<void>.delayed(Duration.zero);

    await expectLater(
      () => notifier.updateRole(userId: 'u1', role: 'admin'),
      throwsA(isA<Exception>()),
    );
  });
}
