import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme.dart';
import '../providers/auth_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(authProvider.notifier).checkAuth();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SP.bg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: SP.glow,
                    blurRadius: 60,
                    spreadRadius: 20,
                  ),
                ],
              ),
              child: const Icon(
                Icons.radio,
                size: 100,
                color: SP.accent,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'StreamPulse',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: SP.text1,
                  ),
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(color: SP.accent),
          ],
        ),
      ),
    );
  }
}
