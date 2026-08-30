import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import '../../../../app/theme.dart';
import '../../data/stream_repository.dart';
import '../../domain/stream_model.dart';
import '../providers/stream_provider.dart';
import '../widgets/audio_waveform.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../app/constants.dart';
import '../../../music/data/music_repository.dart';
import '../../../music/domain/music_model.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/domain/auth_state.dart';

class BroadcasterScreen extends ConsumerStatefulWidget {
  const BroadcasterScreen({super.key});

  @override
  ConsumerState<BroadcasterScreen> createState() => _BroadcasterScreenState();
}

class _BroadcasterScreenState extends ConsumerState<BroadcasterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _selectedFormat = 'mp3';
  bool _isCreating = false;
  StreamModel? _activeStream;
  bool _isBroadcasting = false;

  // Audio recording
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _audioSub;
  CancelToken? _broadcastCancelToken;

  // Listeners tracking
  List<Map<String, dynamic>> _listeners = [];
  Timer? _listenerTimer;

  // Music library
  List<MusicModel> _myMusic = [];
  bool _isLoadingMusic = false;

  @override
  void initState() {
    super.initState();
    _listenerTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_activeStream != null && mounted) {
        _fetchListeners(_activeStream!.id);
        _refreshActiveStream(_activeStream!.id);
      }
    });
    _loadMyMusic();
  }

  @override
  void dispose() {
    _listenerTimer?.cancel();
    _stopBroadcasting();
    _recorder.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _fetchListeners(String streamId) async {
    try {
      final dio = ref.read(dioProvider);
      final response =
          await dio.get(ApiEndpoints.streamListeners(streamId));
      final body = response.data as Map<String, dynamic>;
      final data = body['data'] as Map<String, dynamic>;
      final list = data['listeners'] as List<dynamic>? ?? [];
      if (mounted) {
        setState(() => _listeners = list.cast<Map<String, dynamic>>());
      }
    } catch (_) {}
  }

  Future<void> _refreshActiveStream(String streamId) async {
    try {
      final repo = ref.read(streamRepositoryProvider);
      final updated = await repo.getStream(streamId);
      if (mounted) setState(() => _activeStream = updated);
    } catch (_) {}
  }

  Future<void> _createStream() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isCreating = true);
    try {
      await ref.read(streamListProvider.notifier).createStream(
            title: _titleController.text.trim(),
            description: _descriptionController.text.trim(),
            format: _selectedFormat,
          );
      _titleController.clear();
      _descriptionController.clear();
      if (mounted) context.showSnackBar('Stream created');
    } catch (e) {
      if (mounted) {
        context.showSnackBar('Failed to create stream: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _startStream(String streamId) async {
    try {
      final repo = ref.read(streamRepositoryProvider);
      await repo.startStream(streamId);
      final updated = await repo.getStream(streamId);
      setState(() {
        _activeStream = updated;
        _listeners = [];
      });

      // Start mic broadcasting
      await _startBroadcasting(streamId);

      if (mounted) context.showSnackBar('You are LIVE!');
    } catch (e) {
      if (mounted) {
        context.showSnackBar('Failed to start: $e', isError: true);
      }
    }
  }

  Future<void> _startBroadcasting(String streamId) async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        context.showSnackBar('Microphone permission denied', isError: true);
      }
      return;
    }

    final token = await ref.read(secureStorageProvider).getAccessToken();
    _broadcastCancelToken = CancelToken();

    // Start recording as a stream of PCM data
    final recordStream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
    ));

    setState(() => _isBroadcasting = true);

    // Pipe audio data to the backend via chunked HTTP POST
    final url =
        '${AppConstants.apiBaseUrl}${ApiEndpoints.streamBroadcast(streamId)}';

    // Create a stream controller that we'll feed audio into
    final controller = StreamController<List<int>>();

    _audioSub = recordStream.listen(
      (data) {
        if (!controller.isClosed) {
          controller.add(data);
        }
      },
      onDone: () {
        if (!controller.isClosed) controller.close();
      },
      onError: (e) {
        if (!controller.isClosed) controller.close();
      },
    );

    // Send the stream to the backend
    final broadcastDio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: Duration.zero,
      sendTimeout: Duration.zero,
    ));

    broadcastDio
        .post(
      url,
      data: controller.stream,
      options: Options(
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/octet-stream',
          'Transfer-Encoding': 'chunked',
        },
      ),
      cancelToken: _broadcastCancelToken,
    )
        .then<void>((_) {}, onError: (e) {
      if (!CancelToken.isCancel(e)) {
        debugPrint('Broadcast connection ended: $e');
      }
    });
  }

  Future<void> _stopBroadcasting() async {
    _broadcastCancelToken?.cancel();
    _broadcastCancelToken = null;
    await _audioSub?.cancel();
    _audioSub = null;
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
    if (mounted) setState(() => _isBroadcasting = false);
  }

  Future<void> _stopStream(String streamId) async {
    try {
      await _stopBroadcasting();
      final repo = ref.read(streamRepositoryProvider);
      await repo.stopStream(streamId);
      setState(() {
        _activeStream = null;
        _listeners = [];
      });
      ref.read(streamListProvider.notifier).fetchStreams();
      if (mounted) context.showSnackBar('Stream stopped');
    } catch (e) {
      if (mounted) {
        context.showSnackBar('Failed to stop: $e', isError: true);
      }
    }
  }

  Future<void> _loadMyMusic() async {
    setState(() => _isLoadingMusic = true);
    try {
      final repo = ref.read(musicRepositoryProvider);
      final music = await repo.listMusic();
      if (mounted) setState(() => _myMusic = music);
    } catch (_) {}
    if (mounted) setState(() => _isLoadingMusic = false);
  }

  void _showAddMusicDialog() {
    final titleCtrl = TextEditingController();
    final artistCtrl = TextEditingController();
    final albumCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final durationCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: SP.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Add Music by URL',
            style: TextStyle(color: SP.text1, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: urlCtrl,
                      decoration: InputDecoration(
                        labelText: 'Audio URL',
                        hintText: 'https://example.com/song.mp3',
                        prefixIcon: const Icon(Icons.link, color: SP.text3),
                        filled: true,
                        fillColor: SP.surfaceVariant,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      style: const TextStyle(color: SP.text1),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'URL is required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: titleCtrl,
                      decoration: InputDecoration(
                        labelText: 'Title',
                        prefixIcon: const Icon(Icons.music_note, color: SP.text3),
                        filled: true,
                        fillColor: SP.surfaceVariant,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      style: const TextStyle(color: SP.text1),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Title is required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: artistCtrl,
                      decoration: InputDecoration(
                        labelText: 'Artist',
                        prefixIcon: const Icon(Icons.person, color: SP.text3),
                        filled: true,
                        fillColor: SP.surfaceVariant,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      style: const TextStyle(color: SP.text1),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Artist is required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: albumCtrl,
                      decoration: InputDecoration(
                        labelText: 'Album (optional)',
                        prefixIcon: const Icon(Icons.album, color: SP.text3),
                        filled: true,
                        fillColor: SP.surfaceVariant,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      style: const TextStyle(color: SP.text1),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: durationCtrl,
                      decoration: InputDecoration(
                        labelText: 'Duration (seconds)',
                        hintText: '180',
                        prefixIcon: const Icon(Icons.timer, color: SP.text3),
                        filled: true,
                        fillColor: SP.surfaceVariant,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      style: const TextStyle(color: SP.text1),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: SP.text3)),
            ),
            FilledButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      setDialogState(() => isSubmitting = true);
                      try {
                        final repo = ref.read(musicRepositoryProvider);
                        await repo.addMusicByUrl(
                          title: titleCtrl.text.trim(),
                          artist: artistCtrl.text.trim(),
                          album: albumCtrl.text.trim(),
                          url: urlCtrl.text.trim(),
                          duration: int.tryParse(durationCtrl.text.trim()) ?? 0,
                        );
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        if (mounted) {
                          context.showSnackBar('Music added successfully');
                          _loadMyMusic();
                        }
                      } catch (e) {
                        setDialogState(() => isSubmitting = false);
                        if (mounted) {
                          context.showSnackBar('Failed to add music: $e',
                              isError: true);
                        }
                      }
                    },
              style: FilledButton.styleFrom(
                backgroundColor: SP.accent,
                foregroundColor: SP.btnText,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: SP.btnText),
                    )
                  : const Text('Add'),
            ),
          ],
        ),
      ),
    );
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
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Broadcaster'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_activeStream != null) _buildLiveCard(),
            if (_activeStream == null) ...[
              Text(
                'Create New Stream',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: SP.text1,
                    ),
              ),
              const SizedBox(height: 16),
              _buildCreateForm(),
              const SizedBox(height: 32),
            ],
            Text(
              'Your Streams',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: SP.text1,
                  ),
            ),
            const SizedBox(height: 12),
            _buildStreamsList(),
            const SizedBox(height: 32),
            _buildMusicLibrarySection(),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveCard() {
    return Card(
      color: SP.liveBg.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: SP.liveBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle,
                          size: 8,
                          color: _isBroadcasting ? SP.liveText : SP.liveText.withValues(alpha: 0.5)),
                      const SizedBox(width: 4),
                      Text(
                        _isBroadcasting ? 'LIVE' : 'STARTING...',
                        style: const TextStyle(
                          color: SP.liveText,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                const Icon(Icons.headphones, size: 18, color: SP.text3),
                const SizedBox(width: 4),
                Text(
                  '${_activeStream!.listenerCount}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: SP.text1,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _activeStream!.title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: SP.text1,
                  ),
            ),
            const SizedBox(height: 12),
            AudioWaveform(
              isActive: _isBroadcasting,
              color: SP.liveBg,
              barCount: 30,
              height: 40,
            ),
            const SizedBox(height: 16),

            // Listeners
            if (_listeners.isNotEmpty) ...[
              Text(
                'Listening now:',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: SP.text1,
                    ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _listeners.map((l) {
                  final name = l['username'] as String? ?? '?';
                  return Chip(
                    backgroundColor: SP.surfaceVariant,
                    avatar: CircleAvatar(
                      backgroundColor: SP.accent,
                      child: Text(name[0].toUpperCase(),
                          style: const TextStyle(
                              color: SP.btnText,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ),
                    label: Text(name, style: const TextStyle(color: SP.text1)),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ] else ...[
              Text(
                'No listeners yet',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: SP.text3,
                    ),
              ),
              const SizedBox(height: 16),
            ],

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _stopStream(_activeStream!.id),
                icon: const Icon(Icons.stop),
                label: const Text('Stop Broadcasting'),
                style: FilledButton.styleFrom(
                  backgroundColor: SP.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: 'Stream Title',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.title),
            ),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Title is required' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _descriptionController,
            decoration: InputDecoration(
              labelText: 'Description',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.description),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _selectedFormat,
            decoration: InputDecoration(
              labelText: 'Audio Format',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.audiotrack),
            ),
            items: const [
              DropdownMenuItem(value: 'mp3', child: Text('MP3')),
              DropdownMenuItem(value: 'aac', child: Text('AAC')),
              DropdownMenuItem(value: 'ogg', child: Text('OGG')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _selectedFormat = v);
            },
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _isCreating ? null : _createStream,
            icon: _isCreating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.add),
            label: Text(_isCreating ? 'Creating...' : 'Create Stream'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStreamsList() {
    return Consumer(
      builder: (context, ref, _) {
        final streamsAsync = ref.watch(streamListProvider);
        final authState = ref.watch(authProvider);
        final currentUserId =
            authState is AuthAuthenticated ? authState.user.id : '';
        return streamsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: SP.accent)),
          error: (error, _) => Text('Error: $error', style: const TextStyle(color: SP.error)),
          data: (allStreams) {
            // Le backend renvoie tous les streams : on ne garde que ceux
            // du broadcaster connecte (seul lui peut les demarrer/arreter).
            final streams = allStreams
                .where((s) => s.ownerId == currentUserId)
                .toList();
            if (streams.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No streams yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: SP.text3)),
              );
            }
            return Column(
              children: streams.map((stream) {
                final isActive = _activeStream?.id == stream.id;
                return Card(
                  color: SP.surface,
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: isActive
                        ? const BorderSide(color: SP.liveBg, width: 2)
                        : BorderSide.none,
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: Icon(
                      stream.isLive ? Icons.radio : Icons.radio_outlined,
                      color: stream.isLive ? SP.liveBg : SP.text3,
                    ),
                    title: Text(stream.title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: SP.text1,
                            )),
                    subtitle: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: stream.isLive ? SP.liveBg : SP.text3,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          stream.isLive ? 'LIVE' : stream.status.toUpperCase(),
                          style: TextStyle(
                              fontSize: 11,
                              color: stream.isLive ? SP.liveText : SP.text3,
                              fontWeight: FontWeight.bold),
                        ),
                        if (stream.isLive) ...[
                          const SizedBox(width: 12),
                          const Icon(Icons.headphones,
                              size: 14, color: SP.text3),
                          const SizedBox(width: 4),
                          Text('${stream.listenerCount}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: SP.text2)),
                        ],
                      ],
                    ),
                    trailing: SizedBox(
                      width: 80,
                      height: 32,
                      child: stream.isLive
                          ? TextButton(
                              onPressed: () => _stopStream(stream.id),
                              style: TextButton.styleFrom(
                                foregroundColor: SP.error,
                                padding: EdgeInsets.zero,
                              ),
                              child: const Text('Stop', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                            )
                          : TextButton(
                              onPressed: _activeStream != null ? null : () => _startStream(stream.id),
                              style: TextButton.styleFrom(
                                foregroundColor: SP.accent,
                                padding: EdgeInsets.zero,
                              ),
                              child: const Text('Go Live', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                            ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        );
      },
    );
  }

  Widget _buildMusicLibrarySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Music Library',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: SP.text1,
                  ),
            ),
            IconButton(
              onPressed: _loadMyMusic,
              icon: const Icon(Icons.refresh, color: SP.text3, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Add Music card
        GestureDetector(
          onTap: _showAddMusicDialog,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SP.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: SP.accent.withValues(alpha: 0.3), width: 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: SP.primaryGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.add, color: SP.btnText, size: 24),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add Music',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: SP.text1,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Add a track by URL',
                        style: TextStyle(fontSize: 12, color: SP.text3),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: SP.text3),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Music list
        if (_isLoadingMusic)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: CircularProgressIndicator(color: SP.accent),
            ),
          )
        else if (_myMusic.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No music uploaded yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: SP.text3),
            ),
          )
        else
          ..._myMusic.map((track) => Card(
                color: SP.surface,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: SP.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.music_note,
                        color: SP.accent, size: 20),
                  ),
                  title: Text(
                    track.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: SP.text1,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    track.artist.isNotEmpty ? track.artist : 'Unknown artist',
                    style: const TextStyle(fontSize: 12, color: SP.text3),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    track.formattedDuration,
                    style: const TextStyle(fontSize: 12, color: SP.text3),
                  ),
                ),
              )),
      ],
    );
  }
}
