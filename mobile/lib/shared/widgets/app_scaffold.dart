import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/domain/auth_state.dart';
import 'live_mini_player.dart';
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
      const _NavTab(Icons.radio_outlined, Icons.radio, 'DIRECT'),
      const _NavTab(Icons.queue_music_outlined, Icons.queue_music, 'PLAYLISTS'),
      const _NavTab(Icons.favorite_border, Icons.favorite, 'FAVORIS'),
      const _NavTab(Icons.person_outline, Icons.person, 'PROFIL'),
      if (isAdmin) const _NavTab(Icons.admin_panel_settings_outlined, Icons.admin_panel_settings, 'ADMIN'),
    ];

    return Scaffold(
      body: Column(
        children: [
          Expanded(child: child),
          // Les deux lecteurs suivent des systèmes distincts (flux en direct
          // vs. musique téléversée) et peuvent être actifs simultanément :
          // on empile leurs barres plutôt que de n'en montrer qu'une.
          const LiveMiniPlayer(),
          const MiniPlayer(),
        ],
      ),
      extendBody: false,
      bottomNavigationBar: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            height: 80 + MediaQuery.of(context).padding.bottom,
            decoration: BoxDecoration(
              color: context.colors.navBg,
              boxShadow: [BoxShadow(color: context.colors.navShadow, offset: const Offset(0, -8), blurRadius: 24)],
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
      backgroundColor: context.colors.surface,
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
                color: context.colors.text3.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            CircleAvatar(
              radius: 40,
              backgroundColor: context.colors.surfaceVariant,
              child: Text(
                user.username.isNotEmpty ? user.username[0].toUpperCase() : '?',
                style: TextStyle(fontSize: 32, color: context.colors.accent, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 16),
            Text(user.username, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: context.colors.text1)),
            const SizedBox(height: 4),
            Text(user.email, style: TextStyle(fontSize: 14, color: context.colors.text3)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: context.colors.surfaceVariant,
                borderRadius: BorderRadius.circular(9999),
              ),
              child: Text(
                user.role.toUpperCase(),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: context.colors.accent),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(sheetCtx).pop();
                  context.push('/account');
                },
                icon: const Icon(Icons.manage_accounts_outlined, size: 18),
                label: const Text('Mon compte'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.colors.accent,
                  side: BorderSide(color: context.colors.accent),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                Navigator.of(sheetCtx).pop();
                ref.read(authProvider.notifier).logout();
                context.go('/login');
              },
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Sign Out'),
              style: TextButton.styleFrom(foregroundColor: context.colors.text3),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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
    final color = selected ? context.colors.accent : context.colors.textMuted;
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
