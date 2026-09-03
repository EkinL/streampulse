import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import '../../../../app/constants.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/storage/secure_storage.dart';

/// Etat de la capture micro du diffuseur.
class BroadcastState {
  final String? streamId;
  final bool isBroadcasting;

  /// Passage a l'antenne, pour le compteur de duree de la console.
  final DateTime? startedAt;

  /// Coupures de l'envoi vers le backend depuis le passage a l'antenne.
  final int dropCount;

  const BroadcastState({
    this.streamId,
    this.isBroadcasting = false,
    this.startedAt,
    this.dropCount = 0,
  });

  bool isBroadcastingStream(String id) => isBroadcasting && streamId == id;

  BroadcastState copyWith({int? dropCount}) => BroadcastState(
    streamId: streamId,
    isBroadcasting: isBroadcasting,
    startedAt: startedAt,
    dropCount: dropCount ?? this.dropCount,
  );
}

/// Capture le micro et le pousse au backend (POST chunke sur
/// /streams/:id/broadcast) pendant toute la duree du live.
///
/// Vit dans un provider, pas dans l'ecran de la console : la console est une
/// route pleine page, la quitter (retour a la liste, detail d'un flux)
/// detruisait l'ecran et avec lui la capture, alors que le flux restait
/// "live" cote serveur. Les auditeurs se connectaient a un direct muet.
/// Symetrique de LiveStreamNotifier pour l'ecoute.
class BroadcastNotifier extends StateNotifier<BroadcastState> {
  final SecureStorageService _secureStorage;
  final AudioRecorder _recorder;
  final String _baseUrl;
  final Duration _retryDelay;

  StreamSubscription<Uint8List>? _micSub;
  StreamController<List<int>>? _upload;
  CancelToken? _cancelToken;

  BroadcastNotifier(
    this._secureStorage, {
    AudioRecorder? recorder,
    String baseUrl = AppConstants.apiBaseUrl,
    Duration retryDelay = const Duration(seconds: 2),
  }) : _recorder = recorder ?? AudioRecorder(),
       _baseUrl = baseUrl,
       _retryDelay = retryDelay,
       super(const BroadcastState());

  /// Demarre la capture pour [streamId]. Renvoie false si la permission
  /// micro est refusee (rien n'est demarre). Sans effet si ce flux est deja
  /// a l'antenne ; un autre flux en cours est coupe d'abord.
  Future<bool> start(String streamId) async {
    if (state.isBroadcastingStream(streamId)) return true;
    if (state.isBroadcasting) await stop();

    if (!await _recorder.hasPermission()) return false;

    // PCM16 16 kHz mono : le lecteur des auditeurs (LiveStreamNotifier)
    // attend exactement ce format.
    final mic = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );

    state = BroadcastState(
      streamId: streamId,
      isBroadcasting: true,
      startedAt: DateTime.now(),
    );

    _micSub = mic.listen(
      (data) {
        final upload = _upload;
        if (upload != null && !upload.isClosed) upload.add(data);
      },
      onDone: () => _upload?.close(),
      onError: (Object _) => _upload?.close(),
    );
    unawaited(_openUpload(streamId));
    return true;
  }

  /// Ouvre le POST chunke et y branche le micro. Si la connexion tombe
  /// alors qu'on est toujours a l'antenne, on la rouvre : avant, une seule
  /// coupure (backend redemarre, reseau) laissait un direct muet jusqu'a
  /// l'arret manuel.
  Future<void> _openUpload(String streamId) async {
    final token = await _secureStorage.getAccessToken();
    final upload = StreamController<List<int>>();
    final cancel = CancelToken();
    _upload = upload;
    _cancelToken = cancel;

    final dio = Dio(
      BaseOptions(
        connectTimeout: AppConstants.connectionTimeout,
        receiveTimeout: Duration.zero,
        sendTimeout: Duration.zero,
      ),
    );

    Object? failure;
    try {
      await dio.post<void>(
        '$_baseUrl${ApiEndpoints.streamBroadcast(streamId)}',
        data: upload.stream,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/octet-stream',
            'Transfer-Encoding': 'chunked',
          },
        ),
        cancelToken: cancel,
      );
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) return;
      failure = e;
    }
    // Ce tuyau ne mene plus nulle part : les chunks du micro sont perdus
    // jusqu'a la reouverture, c'est la coupure.
    if (_upload == upload) _upload = null;
    unawaited(upload.close());

    // Arret volontaire entre-temps : rien a faire.
    if (!mounted ||
        !state.isBroadcastingStream(streamId) ||
        _cancelToken != cancel) {
      return;
    }
    debugPrint('broadcast upload ended: ${failure ?? 'closed by server'}');
    state = state.copyWith(dropCount: state.dropCount + 1);

    // Reponse du serveur (flux arrete, session expiree, pas proprietaire) :
    // inutile d'insister, seul un nouveau depart peut corriger.
    if (failure is DioException && failure.response != null) return;

    await Future<void>.delayed(_retryDelay);
    if (mounted &&
        state.isBroadcastingStream(streamId) &&
        _cancelToken == cancel) {
      await _openUpload(streamId);
    }
  }

  Future<void> stop() async {
    _cancelToken?.cancel();
    _cancelToken = null;
    await _micSub?.cancel();
    _micSub = null;
    await _upload?.close();
    _upload = null;
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
    if (mounted) state = const BroadcastState();
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _micSub?.cancel();
    _upload?.close();
    _recorder.dispose();
    super.dispose();
  }
}

final broadcastProvider =
    StateNotifierProvider<BroadcastNotifier, BroadcastState>((ref) {
      return BroadcastNotifier(ref.read(secureStorageProvider));
    });
