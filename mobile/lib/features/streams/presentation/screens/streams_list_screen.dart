import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../app/theme.dart';
import '../providers/stream_provider.dart';
import '../widgets/stream_card.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/domain/auth_state.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../shared/providers/player_provider.dart';
import '../../../music/presentation/providers/music_provider.dart';
import '../../../music/presentation/providers/music_favorites_provider.dart';
import '../../../music/presentation/widgets/music_tile.dart';
import '../../../../shared/widgets/edit_dialog.dart';
import '../../../favorites/presentation/providers/favorites_provider.dart';

class StreamsListScreen extends ConsumerStatefulWidget {
  const StreamsListScreen({super.key});

  @override
  ConsumerState<StreamsListScreen> createState() => _StreamsListScreenState();
}

enum _StreamSort { popular, recent }

class _StreamsListScreenState extends ConsumerState<StreamsListScreen> {
  Timer? _refreshTimer;
  _StreamSort _sort = _StreamSort.popular;

  @override
  void initState() {
    super.initState();
    // Fetch music favorites on init
    Future.microtask(() {
      ref.read(musicFavoritesProvider.notifier).fetch();
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) ref.read(streamListProvider.notifier).fetchStreams();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final streamsAsync = ref.watch(streamListProvider);
    final musicAsync = ref.watch(musicListProvider);
    final favoriteIds = ref.watch(favoriteIdsProvider);
    final authState = ref.watch(authProvider);
    final isBroadcaster =
        authState is AuthAuthenticated && authState.user.isBroadcaster;
    final currentUserId =
        authState is AuthAuthenticated ? authState.user.id : '';

    return Scaffold(
      backgroundColor: SP.altBg,
      body: RefreshIndicator(
        color: SP.accent,
        backgroundColor: SP.surface,
        onRefresh: () async {
          await ref.read(streamListProvider.notifier).fetchStreams();
        },
        child: CustomScrollView(
          slivers: [
            // App bar
            SliverAppBar(
              floating: true,
              backgroundColor: SP.surface,
              title: const Text('StreamPulse', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5, fontSize: 20)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.search, color: SP.text1, size: 22),
                  onPressed: () => context.push('/search'),
                ),
              ],
            ),
            // Content
            streamsAsync.when(
              loading: () => _buildShimmerList(),
              error: (error, _) => SliverFillRemaining(child: _buildErrorState(error.toString())),
              data: (streams) {
                if (streams.isEmpty) {
                  return SliverFillRemaining(child: _buildEmptyState());
                }

                final liveStreams = streams.where((s) => s.isLive).toList();
                final allStreams = streams;

                // Populaires : en direct d'abord, puis par nombre d'auditeurs
                // décroissant. Récents : par date de création décroissante.
                final sortedStreams = [...allStreams]..sort((a, b) {
                    if (_sort == _StreamSort.recent) {
                      return b.createdAt.compareTo(a.createdAt);
                    }
                    if (a.isLive != b.isLive) return a.isLive ? -1 : 1;
                    return b.listenerCount.compareTo(a.listenerCount);
                  });

                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // Hero card (first live stream or first stream)
                      if (allStreams.isNotEmpty) _buildHeroCard(liveStreams.isNotEmpty ? liveStreams.first : allStreams.first),
                      const SizedBox(height: 32),

                      // Section header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Flux actifs',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: SP.text1),
                          ),
                          Row(
                            children: [
                              _FilterChip(
                                label: 'Populaires',
                                selected: _sort == _StreamSort.popular,
                                onTap: () => setState(() => _sort = _StreamSort.popular),
                              ),
                              const SizedBox(width: 8),
                              _FilterChip(
                                label: 'Récents',
                                selected: _sort == _StreamSort.recent,
                                onTap: () => setState(() => _sort = _StreamSort.recent),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Stream cards — pas d'Opacity sur les flux hors ligne : le
                      // contraste doit rester porté par les couleurs de la carte,
                      // pas par une atténuation globale (cf. handoff design).
                      ...sortedStreams.map((stream) {
                        final isFavorite = favoriteIds.contains(stream.id);
                        return StreamCard(
                            stream: stream,
                            favoriteFilled: isFavorite,
                            onTap: () => context.push('/streams/${stream.id}'),
                            onFavorite: () {
                              final notifier = ref.read(favoritesProvider.notifier);
                              final action = isFavorite
                                  ? notifier.remove(stream.id)
                                  : notifier.add(stream.id);
                              action.then((_) {
                                if (!context.mounted) return;
                                context.showSnackBar(isFavorite
                                    ? 'Removed from favorites'
                                    : 'Added to favorites');
                              }).catchError((_) {
                                if (!context.mounted) return;
                                context.showSnackBar('Failed', isError: true);
                              });
                            },
                            onEdit: stream.ownerId == currentUserId
                                ? () => _showEditStreamDialog(context, ref, stream)
                                : null,
                          );
                      }),

                      const SizedBox(height: 32),

                      // Recent Music section
                      const Text(
                        'Recent Music',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: SP.text1),
                      ),
                      const SizedBox(height: 16),
                      musicAsync.when(
                        loading: () => const Center(child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(color: SP.accent),
                        )),
                        error: (e, _) => const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Could not load music', style: TextStyle(color: SP.text3)),
                        ),
                        data: (musicList) {
                          if (musicList.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('No music available', style: TextStyle(color: SP.text3)),
                            );
                          }
                          return Column(
                            children: musicList.take(5).map((music) => MusicTile(
                              music: music,
                              onTap: () {
                                ref.read(playerProvider.notifier).play(music);
                              },
                              onEdit: music.uploadedBy == currentUserId
                                  ? () => _showEditMusicDialog(context, ref, music)
                                  : null,
                            )).toList(),
                          );
                        },
                      ),

                      const SizedBox(height: 16),
                    ]),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      floatingActionButton: isBroadcaster
          ? Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                decoration: BoxDecoration(
                  gradient: SP.primaryGradient,
                  borderRadius: BorderRadius.circular(9999),
                  boxShadow: const [
                    BoxShadow(color: Color(0x406C63FF), blurRadius: 24, offset: Offset(0, 8)),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(9999),
                    onTap: () => context.push('/broadcaster'),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.broadcast_on_personal, size: 16, color: SP.btnText),
                          SizedBox(width: 8),
                          Text(
                            'Broadcast',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: -0.35, color: SP.btnText),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  void _showEditStreamDialog(BuildContext context, WidgetRef ref, dynamic stream) {
    final titleCtrl = TextEditingController(text: stream.title);
    final descCtrl = TextEditingController(text: stream.description);

    showDialog(
      context: context,
      builder: (_) => EditDialog(
        title: 'Edit Stream',
        fields: [
          EditField(label: 'Title', controller: titleCtrl),
          EditField(label: 'Description', controller: descCtrl, maxLines: 3),
        ],
        onSave: () {
          ref.read(streamListProvider.notifier).updateStream(
            id: stream.id,
            title: titleCtrl.text.trim(),
            description: descCtrl.text.trim(),
          ).then((_) {
            if (context.mounted) context.showSnackBar('Stream updated');
          }).catchError((_) {
            if (context.mounted) {
              context.showSnackBar('Update failed', isError: true);
            }
          });
        },
      ),
    );
  }

  void _showEditMusicDialog(BuildContext context, WidgetRef ref, dynamic music) {
    final titleCtrl = TextEditingController(text: music.title);
    final artistCtrl = TextEditingController(text: music.artist);

    showDialog(
      context: context,
      builder: (_) => EditDialog(
        title: 'Edit Track',
        fields: [
          EditField(label: 'Title', controller: titleCtrl),
          EditField(label: 'Artist', controller: artistCtrl),
        ],
        onSave: () {
          // Music update would call the API — placeholder for now
          context.showSnackBar('Track updated');
        },
      ),
    );
  }

  Widget _buildHeroCard(dynamic stream) {
    return GestureDetector(
      onTap: () => context.push('/streams/${stream.id}'),
      child: Container(
        height: 256,
        decoration: BoxDecoration(
          color: SP.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Gradient art background
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      SP.gradEnd.withValues(alpha: 0.7),
                      SP.accent.withValues(alpha: 0.3),
                      SP.bg,
                    ],
                  ),
                ),
              ),
            ),
            // Bottom gradient overlay
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.0, 0.5, 1.0],
                    colors: [Colors.transparent, Colors.transparent, Color(0xFF111125)],
                  ),
                ),
              ),
            ),
            // Content
            Positioned(
              left: 24,
              right: 24,
              bottom: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badges
                  Row(
                    children: [
                      if (stream.isLive)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: SP.liveBg,
                            borderRadius: BorderRadius.circular(9999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(width: 6, height: 6, decoration: const BoxDecoration(color: SP.liveText, shape: BoxShape.circle)),
                              const SizedBox(width: 5),
                              const Text('LIVE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: SP.liveText)),
                            ],
                          ),
                        ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xCC1E1E32),
                          borderRadius: BorderRadius.circular(9999),
                        ),
                        child: Text(
                          '${stream.format.toUpperCase()} \u2022 320 KBPS',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: SP.text2),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Title
                  Text(
                    stream.title,
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: SP.text1, height: 1.25),
                    maxLines: 3,
                  ),
                  if (stream.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      stream.description,
                      style: const TextStyle(fontSize: 14, color: SP.text2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  SliverList _buildShimmerList() {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          return Shimmer.fromColors(
            baseColor: SP.surface,
            highlightColor: SP.surfaceVariant,
            child: Container(
              height: index == 0 ? 256 : 128,
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              decoration: BoxDecoration(color: SP.surface, borderRadius: BorderRadius.circular(12)),
            ),
          );
        },
        childCount: 5,
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: SP.error),
            const SizedBox(height: 16),
            const Text('Something went wrong', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: SP.text1)),
            const SizedBox(height: 8),
            Text(error, style: const TextStyle(color: SP.text2), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => ref.read(streamListProvider.notifier).fetchStreams(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.radio_outlined, size: 80, color: SP.text3),
                SizedBox(height: 16),
                Text('No streams available', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: SP.text2)),
                SizedBox(height: 8),
                Text('Pull down to refresh', style: TextStyle(fontSize: 14, color: SP.text3)),
              ],
            ),
          ),
        ),
      ],
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
    return Material(
      color: selected ? SP.surfaceVariant : Colors.transparent,
      borderRadius: BorderRadius.circular(9999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? SP.text1 : SP.text2,
            ),
          ),
        ),
      ),
    );
  }
}
