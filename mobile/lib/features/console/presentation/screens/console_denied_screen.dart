import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme.dart';
import '../../../auth/domain/auth_state.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// Shown when a signed-in listener reaches the console: they authenticated
/// fine, they simply have no section to open here.
class ConsoleDeniedScreen extends ConsumerWidget {
  const ConsoleDeniedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final username =
        authState is AuthAuthenticated ? authState.user.username : null;

    return Scaffold(
      backgroundColor: SP.bg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: SP.surfaceVariant,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_outline,
                    size: 34,
                    color: SP.text3,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Console access required',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  username == null
                      ? 'This console is for broadcaster and admin accounts.'
                      : '$username is signed in as a listener. This console is '
                          'for broadcaster and admin accounts — ask an admin to '
                          'change your role, or use the mobile app to listen.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: SP.text3,
                      ),
                ),
                const SizedBox(height: 32),
                OutlinedButton.icon(
                  onPressed: () => ref.read(authProvider.notifier).logout(),
                  icon: const Icon(Icons.logout, size: 16),
                  label: const Text('Sign out'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SP.error,
                    side: const BorderSide(color: SP.error),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
