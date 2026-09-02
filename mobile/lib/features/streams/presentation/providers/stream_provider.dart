import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/stream_repository.dart';
import '../../domain/stream_model.dart';
import '../../../../core/network/api_exceptions.dart';

final streamListProvider =
    StateNotifierProvider<StreamNotifier, AsyncValue<List<StreamModel>>>(
        (ref) {
  return StreamNotifier(ref.read(streamRepositoryProvider));
});

final streamDetailProvider =
    FutureProvider.family<StreamModel, String>((ref, id) async {
  final repo = ref.read(streamRepositoryProvider);
  return repo.getStream(id);
});

class StreamNotifier
    extends StateNotifier<AsyncValue<List<StreamModel>>> {
  final StreamRepository _streamRepository;

  StreamNotifier(this._streamRepository)
      : super(const AsyncValue.loading()) {
    fetchStreams();
  }

  Future<void> fetchStreams() async {
    state = const AsyncValue.loading();
    try {
      final streams = await _streamRepository.listStreams();
      state = AsyncValue.data(streams);
    } on ApiException catch (e, st) {
      state = AsyncValue.error(e.message, st);
    } catch (e, st) {
      state = AsyncValue.error(e.toString(), st);
    }
  }

  Future<void> createStream({
    required String title,
    required String description,
    String format = 'mp3',
  }) async {
    try {
      await _streamRepository.createStream(
        title: title,
        description: description,
        format: format,
      );
      await fetchStreams();
    } on ApiException {
      rethrow;
    }
  }

  Future<void> updateStream({
    required String id,
    required String title,
    required String description,
  }) async {
    try {
      await _streamRepository.updateStream(
        id: id,
        title: title,
        description: description,
      );
      await fetchStreams();
    } on ApiException {
      rethrow;
    }
  }
}
