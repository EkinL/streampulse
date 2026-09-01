import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme.dart';
import '../../../auth/domain/auth_state.dart';
import '../../../auth/domain/user_model.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// A section of the web console.
class ConsoleDestination {
  final String path;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String description;

  const ConsoleDestination({
    required this.path,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.description,
  });
}

const ConsoleDestination _broadcast = ConsoleDestination(
  path: '/broadcaster',
  icon: Icons.podcasts_outlined,
  activeIcon: Icons.podcasts,
  label: 'Broadcast',
  description: 'Go live and manage your streams',
);

const ConsoleDestination _users = ConsoleDestination(
  path: '/admin',
  icon: Icons.admin_panel_settings_outlined,
  activeIcon: Icons.admin_panel_settings,
  label: 'Users',
  description: 'Manage accounts and roles',
);

/// The console sections [user] is allowed to open.
///
/// Empty for a plain listener, which is what makes the console staff-only:
/// the router sends anyone with no destinations to the access-denied page.
List<ConsoleDestination> destinationsFor(UserModel user) => [
      if (user.isBroadcaster) _broadcast,
      if (user.isAdmin) _users,
    ];

/// Below this width the sidebar collapses to an icon rail.
const double _railBreakpoint = 900;

/// Desktop chrome around the console sections: a persistent sidebar on the
/// left, the routed screen on the right.
class ConsoleShell extends ConsumerWidget {
  final Widget child;

  const ConsoleShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    if (authState is! AuthAuthenticated) {
      return Scaffold(
        backgroundColor: context.colors.bg,
        body: Center(child: CircularProgressIndicator(color: context.colors.accent)),
      );
    }

    final expanded = MediaQuery.sizeOf(context).width >= _railBreakpoint;
    final currentPath = GoRouterState.of(context).uri.path;

    return Scaffold(
      backgroundColor: context.colors.bg,
      body: Row(
        children: [
          _ConsoleSidebar(
            user: authState.user,
            currentPath: currentPath,
            expanded: expanded,
          ),
          VerticalDivider(width: 1, thickness: 1, color: context.colors.divider),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _ConsoleSidebar extends ConsumerWidget {
  final UserModel user;
  final String currentPath;
  final bool expanded;

  const _ConsoleSidebar({
    required this.user,
    required this.currentPath,
    required this.expanded,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destinations = destinationsFor(user);

    return Container(
      width: expanded ? 264 : 76,
      color: context.colors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Brand(expanded: expanded),
            const SizedBox(height: 8),
            Divider(height: 1, thickness: 1, color: context.colors.divider),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final destination in destinations)
                    _NavItem(
                      destination: destination,
                      selected: currentPath == destination.path,
                      expanded: expanded,
                      onTap: () => context.go(destination.path),
                    ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: context.colors.divider),
            _UserCard(
              user: user,
              expanded: expanded,
              onSignOut: () => ref.read(authProvider.notifier).logout(),
            ),
          ],
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  final bool expanded;

  const _Brand({required this.expanded});

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: SP.primaryGradient,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: context.colors.glow, blurRadius: 24)],
      ),
      child: const Icon(Icons.wifi_tethering, size: 22, color: SP.btnText),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(expanded ? 20 : 18, 20, 20, 16),
      child: expanded
          ? Row(
              children: [
                mark,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'StreamPulse',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              letterSpacing: -0.6,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'CONSOLE',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: context.colors.accent,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.6,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Center(child: mark),
    );
  }
}

class _NavItem extends StatelessWidget {
  final ConsoleDestination destination;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  const _NavItem({
    required this.destination,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? context.colors.accent : context.colors.text2;

    final content = Row(
      mainAxisAlignment:
          expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
      children: [
        Icon(
          selected ? destination.activeIcon : destination.icon,
          size: 20,
          color: color,
        ),
        if (expanded) ...[
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  destination.label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: color,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  destination.description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.colors.text3,
                        fontSize: 11,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? context.colors.accent.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: expanded ? 12 : 8,
              vertical: 12,
            ),
            child: expanded
                ? content
                : Tooltip(message: destination.label, child: content),
          ),
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final UserModel user;
  final bool expanded;
  final VoidCallback onSignOut;

  const _UserCard({
    required this.user,
    required this.expanded,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = CircleAvatar(
      radius: 18,
      backgroundColor: context.colors.surfaceVariant,
      child: Text(
        user.username.isNotEmpty ? user.username[0].toUpperCase() : '?',
        style: TextStyle(
          color: context.colors.accent,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    if (!expanded) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Tooltip(message: '${user.username} · ${user.role}', child: avatar),
            const SizedBox(height: 8),
            IconButton(
              onPressed: onSignOut,
              icon: const Icon(Icons.logout, size: 18),
              color: context.colors.error,
              tooltip: 'Sign out',
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              avatar,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      user.username,
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      user.email,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.colors.text3,
                            fontSize: 11,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: context.colors.surfaceVariant,
                borderRadius: BorderRadius.circular(9999),
              ),
              child: Text(
                user.role.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: context.colors.accent,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onSignOut,
            icon: const Icon(Icons.logout, size: 16),
            label: const Text('Sign out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.colors.error,
              side: BorderSide(color: context.colors.error),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
