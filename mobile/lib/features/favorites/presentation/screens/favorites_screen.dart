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
      backgroundColor: SP.bg,
      appBar: AppBar(
        backgroundColor: SP.surface,
        foregroundColor: SP.text1,
        title: const Text('Favorites'),
      ),
      body: RefreshIndicator(
        color: SP.accent,
        onRefresh: () async {
          await ref.read(favoritesProvider.notifier).fetch();
        },
        child: favoritesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: SP.accent)),
          error: (error, _) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 64,
                  color: SP.error,
                ),
                const SizedBox(height: 16),
                Text('Error: $error', style: const TextStyle(color: SP.text2)),
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
                    const Icon(
                      Icons.favorite_border,
                      size: 80,
                      color: SP.text3,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No favorites yet',
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: SP.text3,
                              ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Start adding streams to your favorites',
                      style:
                          Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: SP.text3,
                              ),
                    ),
                  ],
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: favorites.length,
              itemBuilder: (context, index) {
                final stream = favorites[index];
                return StreamCard(
                  stream: stream,
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
