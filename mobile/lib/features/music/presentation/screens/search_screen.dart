import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme.dart';
import '../../data/music_repository.dart';
import '../../domain/music_model.dart';
import '../../../streams/domain/stream_model.dart';
import '../../../streams/presentation/widgets/stream_card.dart';
import '../widgets/music_tile.dart';
import '../../../../shared/providers/player_provider.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  bool _isLoading = false;
  List<StreamModel> _streamResults = [];
  List<MusicModel> _musicResults = [];
  bool _hasSearched = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _streamResults = [];
        _musicResults = [];
        _hasSearched = false;
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final repo = ref.read(musicRepositoryProvider);
      final results = await repo.globalSearch(query.trim());
      if (mounted) {
        setState(() {
          _streamResults = results.streams;
          _musicResults = results.music;
          _hasSearched = true;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasSearched = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SP.bg,
      appBar: AppBar(
        backgroundColor: SP.surface,
        foregroundColor: SP.text1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Retour',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: TextField(
          controller: _controller,
          autofocus: true,
          style: const TextStyle(color: SP.text1, fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Search streams and music...',
            hintStyle: const TextStyle(color: SP.text3, fontSize: 16),
            filled: true,
            fillColor: SP.surfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            prefixIcon: const Icon(Icons.search, color: SP.text3, size: 20),
            suffixIcon: _controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, color: SP.text3, size: 20),
                    tooltip: 'Effacer',
                    onPressed: () {
                      _controller.clear();
                      _onQueryChanged('');
                    },
                  )
                : null,
          ),
          onChanged: _onQueryChanged,
        ),
        titleSpacing: 0,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: SP.accent),
      );
    }

    if (!_hasSearched) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: SP.text3),
            SizedBox(height: 16),
            Text(
              'Search for streams and music',
              style: TextStyle(fontSize: 16, color: SP.text3),
            ),
          ],
        ),
      );
    }

    if (_streamResults.isEmpty && _musicResults.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: SP.text3),
            SizedBox(height: 16),
            Text(
              'No results found',
              style: TextStyle(fontSize: 16, color: SP.text3),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_streamResults.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Streams',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: SP.text1,
              ),
            ),
          ),
          ..._streamResults.map((stream) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: StreamCard(
                  stream: stream,
                  onTap: () => context.push('/streams/${stream.id}'),
                  onFavorite: () {},
                ),
              )),
          const SizedBox(height: 24),
        ],
        if (_musicResults.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Music',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: SP.text1,
              ),
            ),
          ),
          ..._musicResults.map((music) => MusicTile(
                music: music,
                onTap: () {
                  ref.read(playerProvider.notifier).play(music);
                },
              )),
        ],
      ],
    );
  }
}
