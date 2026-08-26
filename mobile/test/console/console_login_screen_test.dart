import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:streampulse/app/theme.dart';
import 'package:streampulse/features/console/presentation/screens/console_login_screen.dart';

void main() {
  setUpAll(() {
    // Keep the test hermetic: no font downloads.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('shows console branding and no sign-up path', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const ConsoleLoginScreen(),
        ),
      ),
    );

    expect(find.text('StreamPulse'), findsOneWidget);
    expect(find.text('BROADCASTER & ADMIN CONSOLE'), findsOneWidget);

    // The console never offers registration; accounts are provisioned by an
    // admin, unlike the mobile login screen.
    expect(find.textContaining('Sign Up'), findsNothing);
    expect(find.textContaining('OR CONNECT WITH'), findsNothing);
  });

  testWidgets('asks for email and password', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const ConsoleLoginScreen(),
        ),
      ),
    );

    expect(find.text('EMAIL ADDRESS'), findsOneWidget);
    expect(find.text('PASSWORD'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
  });
}
