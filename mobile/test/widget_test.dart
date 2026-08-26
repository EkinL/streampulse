// Smoke test: verifie que l'app demarre, que le routeur resout la route
// initiale et que sans session stockee on aboutit sur l'ecran de connexion.
//
// Le stockage securise est remplace par un faux : en test widget il n'y a
// pas de plateforme native, les appels de canal ne se terminent jamais.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:streampulse/features/auth/data/auth_local_source.dart';
import 'package:streampulse/features/auth/presentation/screens/login_screen.dart';
import 'package:streampulse/features/auth/presentation/screens/splash_screen.dart';
import 'package:streampulse/main.dart';

class _FakeAuthLocalSource implements AuthLocalSource {
  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {}

  @override
  Future<String?> getAccessToken() async => null;

  @override
  Future<String?> getRefreshToken() async => null;

  @override
  Future<void> clearTokens() async {}

  @override
  Future<bool> hasValidToken() async => false;
}

void main() {
  testWidgets('l\'app demarre sur le splash puis redirige vers le login',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authLocalSourceProvider.overrideWithValue(_FakeAuthLocalSource()),
        ],
        child: const StreamPulseApp(),
      ),
    );

    // Premier rendu : MaterialApp monte, splash affiche pendant AuthLoading.
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(SplashScreen), findsOneWidget);

    // checkAuth() ne trouve aucun token -> AuthUnauthenticated
    // -> redirection du routeur vers /login.
    // Pas de pumpAndSettle : le splash contient un spinner anime en boucle.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
