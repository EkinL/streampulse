import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/domain/auth_state.dart';
import 'mini_player.dart';

class AppScaffold extends ConsumerWidget {
  final Widget child;

  const AppScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final isAdmin = authState is AuthAuthenticated && authState.user.isAdmin;
    final currentLocation = GoRouterState.of(context).uri.toString();

    int currentIndex = 0;
    if (currentLocation.startsWith('/streams')) {
      currentIndex = 0;
    } else if (currentLocation.startsWith('/playlists')) {
      currentIndex = 1;
    } else if (currentLocation.startsWith('/favorites')) {
      currentIndex = 2;
    } else if (currentLocation.startsWith('/profile')) {
      currentIndex = 3;
    } else if (currentLocation.startsWith('/admin')) {
      currentIndex = isAdmin ? 4 : 0;
    }

    final tabs = <_NavTab>[
      const _NavTab(Icons.radio_outlined, Icons.radio, 'STREAMS'),
      const _NavTab(Icons.queue_music_outlined, Icons.queue_music, 'PLAYLISTS'),
      const _NavTab(Icons.favorite_border, Icons.favorite, 'FAVORITES'),
      const _NavTab(Icons.person_outline, Icons.person, 'PROFILE'),
      if (isAdmin) const _NavTab(Icons.admin_panel_settings_outlined, Icons.admin_panel_settings, 'ADMIN'),
    ];

    return Scaffold(
      body: Column(
        children: [
          Expanded(child: child),
          const MiniPlayer(),
        ],
      ),
      extendBody: false,
      bottomNavigationBar: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            height: 80 + MediaQuery.of(context).padding.bottom,
            decoration: const BoxDecoration(
              color: SP.navBg,
              boxShadow: [BoxShadow(color: SP.navShadow, offset: Offset(0, -8), blurRadius: 24)],
            ),
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(tabs.length, (i) {
                final selected = i == currentIndex.clamp(0, tabs.length - 1);
                return _NavItem(
                  tab: tabs[i],
                  selected: selected,
                  onTap: () => _onTabTap(context, ref, i),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  void _onTabTap(BuildContext context, WidgetRef ref, int index) {
    switch (index) {
      case 0:
        context.go('/streams');
      case 1:
        context.go('/playlists');
      case 2:
        context.go('/favorites');
      case 3:
        _showProfileSheet(context, ref);
      case 4:
        context.go('/admin');
    }
  }

  void _showProfileSheet(BuildContext context, WidgetRef ref) {
    final authState = ref.read(authProvider);
    if (authState is! AuthAuthenticated) return;
    final user = authState.user;

    showModalBottomSheet(
      context: context,
      backgroundColor: SP.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: SP.text3.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            CircleAvatar(
              radius: 40,
              backgroundColor: SP.surfaceVariant,
              child: Text(
                user.username.isNotEmpty ? user.username[0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 32, color: SP.accent, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 16),
            Text(user.username, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: SP.text1)),
            const SizedBox(height: 4),
            Text(user.email, style: const TextStyle(fontSize: 14, color: SP.text3)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: SP.surfaceVariant,
                borderRadius: BorderRadius.circular(9999),
              ),
              child: Text(
                user.role.toUpperCase(),
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: SP.accent),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(sheetCtx).pop();
                  ref.read(authProvider.notifier).logout();
                  context.go('/login');
                },
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Sign Out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: SP.error,
                  side: const BorderSide(color: SP.error),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 4),
            // Droit a l'effacement (RGPD, docs/rgpd.md) : volontairement
            // discret, sous la deconnexion, et toujours confirme.
            TextButton.icon(
              onPressed: () => _confirmDeleteAccount(context, sheetCtx, ref),
              icon: const Icon(Icons.delete_forever_outlined, size: 18),
              label: const Text('Delete my account'),
              style: TextButton.styleFrom(foregroundColor: SP.text3),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

extension on AppScaffold {
  /// Supprime definitivement le compte apres confirmation explicite, puis
  /// renvoie a l'ecran de connexion. En cas d'echec la session reste ouverte
  /// et l'erreur est affichee.
  Future<void> _confirmDeleteAccount(
    BuildContext context,
    BuildContext sheetCtx,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: sheetCtx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'Your account, playlists, favorites and streams will be permanently '
          'deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: TextButton.styleFrom(foregroundColor: SP.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // On ferme la feuille avant d'appeler le serveur : un message d'erreur
    // affiche sous une feuille modale est invisible.
    if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
    try {
      await ref.read(authProvider.notifier).deleteAccount();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete account: $e')),
      );
      return;
    }
    if (context.mounted) context.go('/login');
  }
}

class _NavTab {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavTab(this.icon, this.activeIcon, this.label);
}

class _NavItem extends StatelessWidget {
  final _NavTab tab;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({required this.tab, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? SP.accent : SP.text2.withValues(alpha: 0.6);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? tab.activeIcon : tab.icon, size: 22, color: color),
            const SizedBox(height: 4),
            Text(
              tab.label,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: 0.5, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
