import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:streampulse/core/storage/offline_audio_store.dart';

void main() {
  late Directory tempDir;
  late OfflineAudioStore store;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('offline_store_test');
    store = OfflineAudioStore(baseDirectory: () async => tempDir);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('cache vide au depart', () async {
    expect(await store.cachedTrackIds(), isEmpty);
    expect(await store.localPathFor('t1'), isNull);
  });

  test('commit promeut le .part en fichier definitif', () async {
    final part = await store.partFileFor('t1', '/uploads/song.mp3');
    expect(part.path, endsWith('t1.mp3.part'));
    await part.writeAsString('audio');

    // tant que le .part n'est pas commit, la piste n'est pas en cache
    expect(await store.cachedTrackIds(), isEmpty);

    final file = await store.commit(part);
    expect(file.path, endsWith('t1.mp3'));
    expect(await store.cachedTrackIds(), {'t1'});
    expect(await store.localPathFor('t1'), file.path);
  });

  test('extension inconnue ou trop longue -> .mp3 par defaut', () async {
    final noExt = await store.partFileFor('a', '/uploads/song');
    expect(noExt.path, endsWith('a.mp3.part'));

    final longExt = await store.partFileFor('b', '/uploads/song.verylongext');
    expect(longExt.path, endsWith('b.mp3.part'));

    final ogg = await store.partFileFor('c', 'http://localhost/uploads/x.OGG');
    expect(ogg.path, endsWith('c.ogg.part'));
  });

  test('delete retire la piste du cache', () async {
    final part = await store.partFileFor('t1', '/uploads/song.mp3');
    await part.writeAsString('audio');
    await store.commit(part);

    await store.delete('t1');
    expect(await store.cachedTrackIds(), isEmpty);
    expect(await store.localPathFor('t1'), isNull);
  });

  test('delete d\'une piste absente ne leve pas', () async {
    await store.delete('absent');
  });
}
