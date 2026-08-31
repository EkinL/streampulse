import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme.dart';
import '../../domain/auth_state.dart';
import '../providers/auth_provider.dart';

/// Réunit les deux droits RGPD déjà câblés côté serveur (accès et
/// effacement, voir `docs/rgpd.md`) dans un seul écran découvrable, plutôt
/// que de les laisser uniquement dans la feuille de profil.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    if (authState is! AuthAuthenticated) {
      return Scaffold(
        backgroundColor: context.colors.bg,
        body: Center(child: CircularProgressIndicator(color: context.colors.accent)),
      );
    }
    final user = authState.user;

    return Scaffold(
      backgroundColor: context.colors.bg,
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        foregroundColor: context.colors.text1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Retour',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Mon compte'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [context.colors.accent.withValues(alpha: 0.2), context.colors.accent.withValues(alpha: 0.05)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: context.colors.surfaceVariant,
                  child: Text(
                    user.username.isNotEmpty ? user.username[0].toUpperCase() : '?',
                    style: TextStyle(fontSize: 22, color: context.colors.accent, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.username,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: context.colors.text1)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: context.colors.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          user.role.toUpperCase(),
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.colors.accent),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Vos données',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: context.colors.text1),
          ),
          const SizedBox(height: 4),
          Text(
            'Droit d\'accès et de portabilité : voici l\'intégralité des données liées à votre compte.',
            style: TextStyle(fontSize: 13, color: context.colors.text3, height: 1.4),
          ),
          const SizedBox(height: 12),
          _DataRow(icon: Icons.badge_outlined, label: 'Identifiant', value: user.id),
          _DataRow(icon: Icons.alternate_email, label: 'Email', value: user.email),
          _DataRow(icon: Icons.person_outline, label: 'Nom d\'utilisateur', value: user.username),
          _DataRow(icon: Icons.shield_outlined, label: 'Rôle', value: user.role),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.privacy_tip_outlined, color: context.colors.text2),
            title: Text('Politique de confidentialité', style: TextStyle(color: context.colors.text1, fontWeight: FontWeight.w600)),
            trailing: Icon(Icons.chevron_right, color: context.colors.text3),
            onTap: () => context.push('/privacy'),
          ),
          const SizedBox(height: 24),
          Text(
            'Zone dangereuse',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: context.colors.text1),
          ),
          const SizedBox(height: 4),
          Text(
            'Droit à l\'effacement : votre compte, vos flux, playlists et favoris sont supprimés immédiatement et définitivement.',
            style: TextStyle(fontSize: 13, color: context.colors.text3, height: 1.4),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _confirmDeleteAccount(context, ref),
              icon: const Icon(Icons.delete_forever_outlined, size: 18),
              label: const Text('Supprimer mon compte'),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.colors.error,
                side: BorderSide(color: context.colors.error),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteAccount(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Supprimer votre compte ?'),
        content: const Text(
          'Votre compte, vos playlists, favoris et flux seront supprimés '
          'définitivement. Cette action est irréversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: TextButton.styleFrom(foregroundColor: context.colors.error),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(authProvider.notifier).deleteAccount();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Suppression impossible : $e')),
      );
      return;
    }
    if (context.mounted) context.go('/login');
  }
}

class _DataRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DataRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: context.colors.text3),
          const SizedBox(width: 12),
          SizedBox(
            width: 130,
            child: Text(label, style: TextStyle(fontSize: 14, color: context.colors.text3)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 14, color: context.colors.text1, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
