import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme.dart';
import '../providers/favorites_provider.dart';
import '../../../streams/presentation/widgets/stream_card.dart';
import '../../../../core/utils/extensions.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoritesAsync = ref.watch(favoritesProvider);

    return Scaffold(
      backgroundColor: context.colors.altBg,
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        foregroundColor: context.colors.text1,
        title: const Text('Favoris'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 24),
            child: Center(
              child: favoritesAsync.maybeWhen(
                data: (favorites) {
                  final liveCount = favorites.where((s) => s.isLive).length;
                  return Text(
                    '$liveCount en direct • ${favorites.length} suivis',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.colors.text3),
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: context.colors.accent,
        onRefresh: () async {
          await ref.read(favoritesProvider.notifier).fetch();
        },
        child: favoritesAsync.when(
          loading: () => Center(child: CircularProgressIndicator(color: context.colors.accent)),
          error: (error, _) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: context.colors.error,
                ),
                const SizedBox(height: 16),
                Text('Error: $error', style: TextStyle(color: context.colors.text2)),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    ref.read(favoritesProvider.notifier).fetch();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
          data: (favorites) {
            if (favorites.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.favorite_border,
                      size: 80,
                      color: context.colors.text3,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No favorites yet',
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: context.colors.text3,
                              ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Start adding streams to your favorites',
                      style:
                          Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: context.colors.text3,
                              ),
                    ),
                  ],
                ),
              );
            }
            // Les flux en direct passent avant les flux hors ligne.
            final sorted = [...favorites]..sort((a, b) {
                if (a.isLive == b.isLive) return 0;
                return a.isLive ? -1 : 1;
              });
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              itemCount: sorted.length + 1,
              itemBuilder: (context, index) {
                if (index == sorted.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Touchez le cœur pour retirer un flux des favoris.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: context.colors.textMuted, height: 1.5),
                    ),
                  );
                }
                final stream = sorted[index];
                return StreamCard(
                  stream: stream,
                  favoriteFilled: true,
                  onTap: () => context.push('/streams/${stream.id}'),
                  onFavorite: () {
                    ref
                        .read(favoritesProvider.notifier)
                        .remove(stream.id)
                        .then((_) {
                      if (!context.mounted) return;
                      context.showSnackBar('Removed from favorites');
                    });
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
