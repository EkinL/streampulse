import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../app/theme.dart';
import '../../../../core/utils/extensions.dart';
import '../../../feedback/domain/feedback_model.dart';
import '../../../feedback/domain/feedback_type.dart';
import '../providers/admin_feedback_provider.dart';

String feedbackStatusLabel(String status) {
  switch (status) {
    case 'new':
      return 'Nouveau';
    case 'in_progress':
      return 'En cours';
    case 'resolved':
      return 'Résolu';
    default:
      return status;
  }
}

Color _statusColor(BuildContext context, String status) {
  switch (status) {
    case 'new':
      return context.colors.accent;
    case 'in_progress':
      return const Color(0xFFE0A426);
    case 'resolved':
      return const Color(0xFF3FB27F);
    default:
      return context.colors.text3;
  }
}

FeedbackType? _typeOf(String value) {
  for (final t in FeedbackType.values) {
    if (t.apiValue == value) return t;
  }
  return null;
}

/// Report list and status management: the second tab of [AdminScreen]. Same
/// shell-less pattern as [AdminUsersScreen] - no `Scaffold`/`AppBar` here.
class AdminFeedbackScreen extends ConsumerStatefulWidget {
  const AdminFeedbackScreen({super.key});

  @override
  ConsumerState<AdminFeedbackScreen> createState() => _AdminFeedbackScreenState();
}

class _AdminFeedbackScreenState extends ConsumerState<AdminFeedbackScreen> {
  String? _filter;

  void _setFilter(String? status) {
    setState(() => _filter = status);
    ref.read(adminFeedbackProvider.notifier).fetchFeedback(status: status);
  }

  @override
  Widget build(BuildContext context) {
    final feedbackAsync = ref.watch(adminFeedbackProvider);

    return RefreshIndicator(
      color: context.colors.accent,
      onRefresh: () async {
        await ref.read(adminFeedbackProvider.notifier).fetchFeedback(status: _filter);
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(label: 'Tous', selected: _filter == null, onTap: () => _setFilter(null)),
                  for (final status in feedbackStatuses) ...[
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: feedbackStatusLabel(status),
                      selected: _filter == status,
                      onTap: () => _setFilter(status),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: feedbackAsync.when(
              loading: () => Center(child: CircularProgressIndicator(color: context.colors.accent)),
              error: (error, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Error: $error', style: TextStyle(color: context.colors.text2)),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => ref.read(adminFeedbackProvider.notifier).fetchFeedback(status: _filter),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (reports) {
                if (reports.isEmpty) {
                  return Center(
                    child: Text('No reports found.', style: TextStyle(color: context.colors.text3)),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: reports.length,
                  itemBuilder: (context, index) => _FeedbackCard(report: reports[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      backgroundColor: context.colors.surfaceVariant,
      selectedColor: context.colors.accent.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        color: selected ? context.colors.accent : context.colors.text2,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      side: BorderSide(color: selected ? context.colors.accent : context.colors.divider),
    );
  }
}

class _FeedbackCard extends ConsumerWidget {
  final FeedbackModel report;

  const _FeedbackCard({required this.report});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = _typeOf(report.type);
    final meta = [
      if (report.platform != null && report.platform!.isNotEmpty) report.platform!,
      if (report.appVersion != null && report.appVersion!.isNotEmpty) 'v${report.appVersion}',
      DateFormat.yMMMd().add_jm().format(report.createdAt.toLocal()),
    ].join(' · ');

    return Card(
      color: context.colors.surface,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(type?.icon ?? Icons.chat_bubble_outline, size: 18, color: context.colors.text2),
                const SizedBox(width: 8),
                Text(
                  type?.label ?? report.type,
                  style: TextStyle(fontWeight: FontWeight.w700, color: context.colors.text1),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusColor(context, report.status).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    feedbackStatusLabel(report.status).toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _statusColor(context, report.status),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(report.message, style: TextStyle(color: context.colors.text1, height: 1.4)),
            const SizedBox(height: 10),
            Text(meta, style: TextStyle(fontSize: 12, color: context.colors.text3)),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: DropdownButton<String>(
                value: report.status,
                underline: const SizedBox(),
                borderRadius: BorderRadius.circular(8),
                dropdownColor: context.colors.surfaceVariant,
                style: TextStyle(color: context.colors.text2),
                items: [
                  for (final status in feedbackStatuses)
                    DropdownMenuItem(value: status, child: Text(feedbackStatusLabel(status))),
                ],
                onChanged: (newStatus) {
                  if (newStatus != null && newStatus != report.status) {
                    ref
                        .read(adminFeedbackProvider.notifier)
                        .updateStatus(id: report.id, status: newStatus)
                        .then((_) {
                      if (!context.mounted) return;
                      context.showSnackBar('Signalement marqué ${feedbackStatusLabel(newStatus)}');
                    }).catchError((e) {
                      if (!context.mounted) return;
                      context.showSnackBar('Échec de la mise à jour : $e', isError: true);
                    });
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
