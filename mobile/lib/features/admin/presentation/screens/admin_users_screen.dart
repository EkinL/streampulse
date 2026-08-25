import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme.dart';
import '../providers/admin_provider.dart';
import '../../../../core/utils/extensions.dart';

class AdminUsersScreen extends ConsumerWidget {
  const AdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(adminProvider);

    return Scaffold(
      backgroundColor: SP.bg,
      appBar: AppBar(
        backgroundColor: SP.surface,
        foregroundColor: SP.text1,
        title: const Text('User Management'),
      ),
      body: RefreshIndicator(
        color: SP.accent,
        onRefresh: () async {
          await ref.read(adminProvider.notifier).fetchUsers();
        },
        child: usersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: SP.accent)),
          error: (error, _) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Error: $error', style: const TextStyle(color: SP.text2)),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    ref.read(adminProvider.notifier).fetchUsers();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
          data: (users) {
            if (users.isEmpty) {
              return const Center(
                child: Text('No users found.', style: TextStyle(color: SP.text3)),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: users.length,
              itemBuilder: (context, index) {
                final user = users[index];
                return Card(
                  color: SP.surface,
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: SP.surfaceVariant,
                      child: Text(
                        user.username.isNotEmpty
                            ? user.username[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: SP.accent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(
                      user.username,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: SP.text1,
                          ),
                    ),
                    subtitle: Text(
                      user.email,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: SP.text3,
                          ),
                    ),
                    trailing: DropdownButton<String>(
                      value: user.role,
                      underline: const SizedBox(),
                      borderRadius: BorderRadius.circular(8),
                      dropdownColor: SP.surfaceVariant,
                      style: TextStyle(color: SP.text2),
                      items: const [
                        DropdownMenuItem(
                          value: 'user',
                          child: Text('User'),
                        ),
                        DropdownMenuItem(
                          value: 'broadcaster',
                          child: Text('Broadcaster'),
                        ),
                        DropdownMenuItem(
                          value: 'admin',
                          child: Text('Admin'),
                        ),
                      ],
                      onChanged: (newRole) {
                        if (newRole != null && newRole != user.role) {
                          ref
                              .read(adminProvider.notifier)
                              .updateRole(
                                userId: user.id,
                                role: newRole,
                              )
                              .then((_) {
                            context.showSnackBar(
                              'Updated ${user.username} to $newRole',
                            );
                          }).catchError((e) {
                            context.showSnackBar(
                              'Failed to update role: $e',
                              isError: true,
                            );
                          });
                        }
                      },
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
