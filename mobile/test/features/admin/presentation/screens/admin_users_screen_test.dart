import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:streampulse/core/network/api_endpoints.dart';
import 'package:streampulse/features/admin/presentation/providers/admin_provider.dart';
import 'package:streampulse/features/admin/presentation/screens/admin_users_screen.dart';
import 'package:streampulse/app/theme.dart';

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

Map<String, dynamic> _userJson(String id, {String username = 'alice', String role = 'user'}) => {
      'id': id,
      'email': '$username@example.com',
      'username': username,
      'role': role,
    };

Future<void> _pump(WidgetTester tester, {required _MockDio dio}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [adminProvider.overrideWith((ref) => AdminNotifier(dio))],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(body: AdminUsersScreen()),
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

  testWidgets('affiche "No users found." pour une liste vide', (tester) async {
    when(() => dio.get(ApiEndpoints.adminUsers)).thenAnswer((_) async => _response({'data': <dynamic>[]}));

    await _pump(tester, dio: dio);
    await tester.pump();

    expect(find.text('No users found.'), findsOneWidget);
  });

  testWidgets('affiche une erreur et permet de reessayer', (tester) async {
    when(() => dio.get(ApiEndpoints.adminUsers)).thenThrow(_errorResponse(500));

    await _pump(tester, dio: dio);
    await tester.pump();

    expect(find.textContaining('Error:'), findsOneWidget);

    when(() => dio.get(ApiEndpoints.adminUsers))
        .thenAnswer((_) async => _response({'data': [_userJson('u1')]}));
    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(find.text('alice'), findsOneWidget);
  });

  testWidgets('liste les utilisateurs avec leur email et role', (tester) async {
    when(() => dio.get(ApiEndpoints.adminUsers)).thenAnswer(
      (_) async => _response({
        'data': [_userJson('u1', username: 'alice', role: 'broadcaster')],
      }),
    );

    await _pump(tester, dio: dio);
    await tester.pump();

    expect(find.text('alice'), findsOneWidget);
    expect(find.text('alice@example.com'), findsOneWidget);
    expect(find.text('Broadcaster'), findsOneWidget);
  });

  testWidgets('changer le role appelle updateRole et rafraichit', (tester) async {
    when(() => dio.get(ApiEndpoints.adminUsers)).thenAnswer(
      (_) async => _response({
        'data': [_userJson('u1', username: 'alice', role: 'user')],
      }),
    );
    await _pump(tester, dio: dio);
    await tester.pump();

    when(() => dio.put(
          ApiEndpoints.adminUserRole('u1'),
          data: {'role': 'admin'},
        )).thenAnswer((_) async => _response(null));
    when(() => dio.get(ApiEndpoints.adminUsers)).thenAnswer(
      (_) async => _response({
        'data': [_userJson('u1', username: 'alice', role: 'admin')],
      }),
    );

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Admin').last);
    await tester.pumpAndSettle();

    verify(() => dio.put(ApiEndpoints.adminUserRole('u1'), data: {'role': 'admin'})).called(1);
    expect(find.text('Updated alice to Admin'), findsOneWidget);
  });

  testWidgets('un echec de changement de role affiche une erreur', (tester) async {
    when(() => dio.get(ApiEndpoints.adminUsers)).thenAnswer(
      (_) async => _response({
        'data': [_userJson('u1', username: 'alice', role: 'user')],
      }),
    );
    await _pump(tester, dio: dio);
    await tester.pump();

    when(() => dio.put(
          ApiEndpoints.adminUserRole('u1'),
          data: {'role': 'admin'},
        )).thenThrow(_errorResponse(403));

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Admin').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Failed to update role'), findsOneWidget);
  });
}
