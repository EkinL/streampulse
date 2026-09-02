import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme.dart';
import '../../../../core/network/api_exceptions.dart';
import '../../../../core/utils/extensions.dart';
import '../../data/feedback_repository.dart';
import '../../domain/feedback_type.dart';

const _messageMaxLength = 4000;

/// Le canal de retour utilisateur (Ce3.4.3) : tout compte peut signaler un
/// bug ou une suggestion depuis l'application, sans passer par un canal
/// externe (issue GitHub, email...). Voir `docs/user-stories.md#us-17`.
class FeedbackScreen extends ConsumerStatefulWidget {
  const FeedbackScreen({super.key});

  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();
  FeedbackType _type = FeedbackType.bug;
  String? _appVersion;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    loadAppVersion().then((version) {
      if (mounted) setState(() => _appVersion = version);
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _submitting = true);
    try {
      // `initState` kicked off the version lookup, but nothing guarantees it
      // finished by the time a fast submit happens; awaiting it here (cheap
      // once cached) is what actually ties the report to a version.
      final appVersion = _appVersion ?? await loadAppVersion();
      await ref.read(feedbackRepositoryProvider).submitFeedback(
            type: _type,
            message: _messageController.text.trim(),
            appVersion: appVersion,
          );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      context.showSnackBar(e.message, isError: true);
      return;
    }
    if (!mounted) return;
    context.showSnackBar('Merci, votre signalement a bien été envoyé.');
    Navigator.of(context).pop();
  }

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
        title: const Text('Signaler un problème'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Un bug, une suggestion ? Décrivez-le ci-dessous, l\'équipe le'
              ' traite depuis son tableau de bord.',
              style: TextStyle(fontSize: 13, color: context.colors.text3, height: 1.4),
            ),
            const SizedBox(height: 20),
            Text(
              'Type',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.colors.text2),
            ),
            const SizedBox(height: 8),
            SegmentedButton<FeedbackType>(
              segments: [
                for (final type in FeedbackType.values)
                  ButtonSegment(value: type, icon: Icon(type.icon, size: 18), label: Text(type.label)),
              ],
              selected: {_type},
              onSelectionChanged: (selection) => setState(() => _type = selection.first),
              style: SegmentedButton.styleFrom(
                backgroundColor: context.colors.surfaceVariant,
                foregroundColor: context.colors.text2,
                selectedBackgroundColor: context.colors.accent,
                selectedForegroundColor: context.colors.onAccent,
                side: BorderSide(color: context.colors.divider),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Message',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.colors.text2),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _messageController,
              minLines: 5,
              maxLines: 10,
              maxLength: _messageMaxLength,
              style: TextStyle(fontSize: 15, color: context.colors.text1),
              decoration: InputDecoration(
                hintText: 'Décrivez le problème ou votre idée aussi précisément que possible…',
                hintStyle: TextStyle(fontSize: 14, color: context.colors.text3),
                filled: true,
                fillColor: context.colors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.colors.accent, width: 1.5),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.colors.error),
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
              validator: (value) {
                final trimmed = value?.trim() ?? '';
                if (trimmed.isEmpty) return 'Un message est requis.';
                if (trimmed.length > _messageMaxLength) {
                  return 'Le message dépasse $_messageMaxLength caractères.';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: context.colors.accent,
                  foregroundColor: context.colors.onAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _submitting
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.onAccent),
                      )
                    : const Text('Envoyer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
