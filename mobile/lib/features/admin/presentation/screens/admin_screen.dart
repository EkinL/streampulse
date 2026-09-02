import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../app/constants.dart';
import '../../../../app/theme.dart';
import '../../../../core/utils/extensions.dart';
import 'admin_feedback_screen.dart';
import 'admin_users_screen.dart';

/// Administration: accounts/roles and the user feedback channel, as two
/// tabs of the same page rather than two separate destinations - they're
/// both "manage what the platform's users are doing" for the same admin
/// audience, and a shared header (Grafana shortcut) makes more sense than
/// duplicating it per screen.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: context.colors.bg,
        appBar: AppBar(
          backgroundColor: context.colors.surface,
          foregroundColor: context.colors.text1,
          title: const Text('Administration'),
          actions: [
            IconButton(
              tooltip: 'Open Grafana dashboard',
              icon: const Icon(Icons.query_stats),
              onPressed: () => _openGrafana(context),
            ),
          ],
          bottom: TabBar(
            indicatorColor: context.colors.accent,
            labelColor: context.colors.accent,
            unselectedLabelColor: context.colors.text3,
            tabs: const [
              Tab(icon: Icon(Icons.people_outline), text: 'Utilisateurs'),
              Tab(icon: Icon(Icons.feedback_outlined), text: 'Signalements'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            AdminUsersScreen(),
            AdminFeedbackScreen(),
          ],
        ),
      ),
    );
  }

  Future<void> _openGrafana(BuildContext context) async {
    try {
      final uri = Uri.parse(AppConstants.grafanaUrl);
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        context.showSnackBar('Could not open Grafana dashboard', isError: true);
      }
    } catch (_) {
      if (context.mounted) {
        context.showSnackBar('Could not open Grafana dashboard', isError: true);
      }
    }
  }
}
