import 'package:flutter/material.dart';
import '../../../../app/theme.dart';

/// Notice d'information (art. 13 RGPD) — accessible avant et après connexion
/// (lien depuis l'inscription, et depuis "Mon compte"). Reprend en langage
/// utilisateur ce que documente `docs/rgpd.md` côté serveur : on ne demande
/// pas de consentement ici, la quasi-totalité du traitement repose sur
/// l'exécution du contrat (faire fonctionner le compte), pas sur le
/// consentement — d'où une simple notice plutôt que des cases à cocher.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
        title: const Text('Politique de confidentialité'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _Section(
            title: 'Ce que nous conservons',
            body:
                'Votre email, votre nom d\'utilisateur et un mot de passe '
                'chiffré (jamais en clair), ainsi que les flux, playlists, '
                'favoris et morceaux liés à votre compte. Par sécurité, '
                'l\'adresse IP et le type d\'appareil sont journalisés '
                'temporairement lors de vos requêtes.',
          ),
          _Section(
            title: 'Pourquoi',
            body:
                'Uniquement pour faire fonctionner le service : créer et '
                'sécuriser votre compte, faire tourner vos flux et '
                'playlists. Aucun profilage, aucune publicité, aucune '
                'revente à un tiers.',
          ),
          _Section(
            title: 'Combien de temps',
            body:
                'Vos données sont conservées tant que votre compte existe. '
                'Elles sont toutes supprimées avec lui, sans délai.',
          ),
          _Section(
            title: 'Vos droits',
            body:
                'Accès : retrouvez l\'ensemble de vos données dans '
                '« Mon compte ». Suppression : le même écran permet '
                'd\'effacer définitivement votre compte et tout ce qui s\'y '
                'rattache. Rectification (email, nom d\'utilisateur) : pas '
                'encore en libre-service, elle passe pour l\'instant par un '
                'administrateur.',
          ),
          SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;

  const _Section({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: context.colors.text1),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(fontSize: 16, height: 1.55, color: context.colors.text2),
          ),
        ],
      ),
    );
  }
}
