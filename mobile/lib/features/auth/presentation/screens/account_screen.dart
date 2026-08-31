import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme.dart';
import '../../../../core/network/api_exceptions.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/providers/theme_provider.dart';
import '../../domain/auth_state.dart';
import '../../domain/user_model.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_form_field.dart';

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
            'Apparence',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: context.colors.text1),
          ),
          const SizedBox(height: 4),
          Text(
            'Choisissez l\'apparence de l\'application, ou suivez les réglages de votre appareil.',
            style: TextStyle(fontSize: 13, color: context.colors.text3, height: 1.4),
          ),
          const SizedBox(height: 12),
          _ThemeModeSelector(themeMode: ref.watch(themeModeProvider)),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: ref.watch(highContrastProvider),
            onChanged: (value) => ref.read(highContrastProvider.notifier).set(value),
            activeTrackColor: context.colors.accent,
            title: Text('Contraste élevé', style: TextStyle(color: context.colors.text1, fontWeight: FontWeight.w600)),
            subtitle: Text(
              'Renforce les contrastes de texte et les bordures pour une meilleure lisibilité.',
              style: TextStyle(fontSize: 12, color: context.colors.text3, height: 1.4),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Taille du texte',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.colors.text2),
          ),
          const SizedBox(height: 8),
          _TextScaleSelector(textScale: ref.watch(textScaleProvider)),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'Vos données',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: context.colors.text1),
                ),
              ),
              TextButton.icon(
                onPressed: () => _editProfile(context, ref, user),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Modifier'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Droit d\'accès et de portabilité : voici l\'intégralité des données liées à votre compte. '
            'Droit de rectification : modifiez votre email ou votre nom d\'utilisateur à tout moment.',
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

  /// Droit de rectification (RGPD art. 16) : jusqu'ici seul un administrateur
  /// pouvait changer l'email ou le nom d'utilisateur, directement en base.
  ///
  /// Le dialogue se contente de collecter les valeurs et se ferme avant tout
  /// appel reseau : `updateProfile` change l'etat de `authProvider`, dont
  /// `GoRouter` ecoute les changements (`refreshListenable`), et le faire
  /// pendant qu'une route de dialogue est encore active fait planter le
  /// framework (assertion `_dependents`), comme pour `_confirmDeleteAccount`.
  Future<void> _editProfile(BuildContext context, WidgetRef ref, UserModel user) async {
    final result = await showDialog<({String email, String username})>(
      context: context,
      builder: (_) => _EditProfileDialog(user: user),
    );
    if (result == null) return;

    try {
      await ref.read(authProvider.notifier).updateProfile(
            email: result.email,
            username: result.username,
          );
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Modification impossible : ${e.message}')),
      );
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Informations mises à jour.')),
    );
  }
}

/// Formulaire du dialogue de rectification. Un widget a part, plutot que des
/// controleurs locaux a `_editProfile`, pour que Flutter dispose lui-meme les
/// `TextEditingController` au bon moment : les disposer a la main juste apres
/// `await showDialog(...)` court-circuite l'animation de sortie du dialogue,
/// encore en train de reconstruire les champs avec des controleurs deja
/// detruits ("used after being disposed").
class _EditProfileDialog extends StatefulWidget {
  final UserModel user;

  const _EditProfileDialog({required this.user});

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _emailController = TextEditingController(text: widget.user.email);
  late final _usernameController = TextEditingController(text: widget.user.username);

  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  void _unfocusAndPop<T>(T value) {
    // Un focus encore actif sur un champ (et sa barre d'outils de selection
    // eventuelle) fait planter le framework s'il est toujours la quand la
    // route du dialogue est retiree.
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Modifier mes informations'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AuthFormField(
              controller: _emailController,
              label: 'Email',
              keyboardType: TextInputType.emailAddress,
              prefixIcon: const Icon(Icons.alternate_email),
              validator: Validators.email,
            ),
            const SizedBox(height: 12),
            AuthFormField(
              controller: _usernameController,
              label: 'Nom d\'utilisateur',
              prefixIcon: const Icon(Icons.person_outline),
              validator: Validators.username,
              textInputAction: TextInputAction.done,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _unfocusAndPop<({String email, String username})?>(null),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            _unfocusAndPop((
              email: _emailController.text.trim(),
              username: _usernameController.text.trim(),
            ));
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _ThemeModeSelector extends ConsumerWidget {
  final ThemeMode themeMode;

  const _ThemeModeSelector({required this.themeMode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SegmentedButton<ThemeMode>(
      segments: const [
        ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined), label: Text('Système')),
        ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Clair')),
        ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Sombre')),
      ],
      selected: {themeMode},
      onSelectionChanged: (selection) {
        ref.read(themeModeProvider.notifier).set(selection.first);
      },
      style: SegmentedButton.styleFrom(
        backgroundColor: context.colors.surfaceVariant,
        foregroundColor: context.colors.text2,
        selectedBackgroundColor: context.colors.accent,
        selectedForegroundColor: context.colors.onAccent,
        side: BorderSide(color: context.colors.divider),
      ),
    );
  }
}

class _TextScaleSelector extends ConsumerWidget {
  final AppTextScale textScale;

  const _TextScaleSelector({required this.textScale});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SegmentedButton<AppTextScale>(
      segments: [
        for (final option in AppTextScale.values)
          ButtonSegment(
            value: option,
            label: Text(
              option.label,
              style: TextStyle(fontSize: 12 + (option.factor ?? 1.0) * 2),
            ),
          ),
      ],
      selected: {textScale},
      onSelectionChanged: (selection) {
        ref.read(textScaleProvider.notifier).set(selection.first);
      },
      style: SegmentedButton.styleFrom(
        backgroundColor: context.colors.surfaceVariant,
        foregroundColor: context.colors.text2,
        selectedBackgroundColor: context.colors.accent,
        selectedForegroundColor: context.colors.onAccent,
        side: BorderSide(color: context.colors.divider),
      ),
    );
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
