import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:streampulse/app/constants.dart';
import 'package:streampulse/core/storage/offline_audio_store.dart';
import 'package:streampulse/shared/providers/offline_provider.dart';

class _MockDio extends Mock implements Dio {}

void main() {
  late Directory tempDir;
  late OfflineAudioStore store;
  late _MockDio dio;
  late OfflineNotifier notifier;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('offline_provider_test');
    store = OfflineAudioStore(baseDirectory: () async => tempDir);
    dio = _MockDio();
    notifier = OfflineNotifier(store, dio);
  });

  tearDown(() {
    notifier.dispose();
    tempDir.deleteSync(recursive: true);
  });

  void stubDownloadOk() {
    when(() => dio.download(any(), any())).thenAnswer((inv) async {
      final savePath = inv.positionalArguments[1] as String;
      File(savePath).writeAsStringSync('audio');
      return Response(requestOptions: RequestOptions());
    });
  }

  test('downloadTrack telecharge, commit et met a jour l\'etat', () async {
    stubDownloadOk();

    await notifier.downloadTrack(id: 't1', url: '/uploads/song.mp3');

    // URL relative resolue en absolue vers l'API
    verify(() =>
            dio.download('${AppConstants.apiBaseUrl}/uploads/song.mp3', any()))
        .called(1);
    expect(notifier.state.isCached('t1'), isTrue);
    expect(notifier.state.isDownloading('t1'), isFalse);
    expect(await notifier.localPathFor('t1'), isNotNull);
  });

  test('downloadTrack est idempotent sur une piste deja en cache', () async {
    stubDownloadOk();

    await notifier.downloadTrack(id: 't1', url: '/uploads/song.mp3');
    await notifier.downloadTrack(id: 't1', url: '/uploads/song.mp3');

    verify(() => dio.download(any(), any())).called(1);
  });

  test('un echec de telechargement ne marque pas la piste en cache', () async {
    when(() => dio.download(any(), any()))
        .thenThrow(DioException(requestOptions: RequestOptions()));

    await expectLater(
      notifier.downloadTrack(id: 't1', url: '/uploads/song.mp3'),
      throwsA(isA<DioException>()),
    );
    expect(notifier.state.isCached('t1'), isFalse);
    expect(notifier.state.isDownloading('t1'), isFalse);
    expect(await notifier.localPathFor('t1'), isNull);
  });

  test('downloadTracks compte les echecs sans s\'arreter', () async {
    when(() => dio.download(any(that: contains('bad')), any()))
        .thenThrow(DioException(requestOptions: RequestOptions()));
    when(() => dio.download(any(that: contains('good')), any()))
        .thenAnswer((inv) async {
      final savePath = inv.positionalArguments[1] as String;
      File(savePath).writeAsStringSync('audio');
      return Response(requestOptions: RequestOptions());
    });

    final failures = await notifier.downloadTracks([
      (id: 'a', url: '/uploads/bad.mp3'),
      (id: 'b', url: '/uploads/good.mp3'),
    ]);

    expect(failures, 1);
    expect(notifier.state.isCached('a'), isFalse);
    expect(notifier.state.isCached('b'), isTrue);
  });

  test('removeTrack supprime le fichier et l\'etat', () async {
    stubDownloadOk();
    await notifier.downloadTrack(id: 't1', url: '/uploads/song.mp3');

    await notifier.removeTrack('t1');

    expect(notifier.state.isCached('t1'), isFalse);
    expect(await store.localPathFor('t1'), isNull);
  });

  test('restaure le cache existant au demarrage', () async {
    stubDownloadOk();
    await notifier.downloadTrack(id: 't1', url: '/uploads/song.mp3');

    final restored = OfflineNotifier(store, dio);
    // le scan du disque est asynchrone : on attend qu'il aboutisse
    await Future.doWhile(() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return !restored.state.isCached('t1');
    }).timeout(const Duration(seconds: 5));
    expect(restored.state.isCached('t1'), isTrue);
    restored.dispose();
  });
}
