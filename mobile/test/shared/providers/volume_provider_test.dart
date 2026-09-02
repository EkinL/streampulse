import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:streampulse/app/constants.dart';
import 'package:streampulse/shared/providers/volume_provider.dart';

class _MemoryStore implements VolumeStore {
  double? value;
  bool fail = false;

  _MemoryStore([this.value]);

  @override
  Future<double?> load() async {
    if (fail) throw StateError('prefs down');
    return value;
  }

  @override
  Future<void> save(double volume) async {
    if (fail) throw StateError('prefs down');
    value = volume;
  }
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  test('demarre sur la valeur par defaut puis restaure la valeur sauvee',
      () async {
    final notifier = VolumeNotifier(_MemoryStore(0.35));
    expect(notifier.state, AppConstants.defaultVolume);

    await _flush();
    expect(notifier.state, 0.35);
  });

  test('set borne dans [0, 1] et persiste', () async {
    final store = _MemoryStore();
    final notifier = VolumeNotifier(store);
    await _flush();

    await notifier.set(1.4);
    expect(notifier.state, 1.0);
    expect(store.value, 1.0);

    await notifier.set(-0.2);
    expect(notifier.state, 0.0);
    expect(notifier.isMuted, isTrue);
  });

  test('toggleMute coupe puis restaure le dernier volume audible', () async {
    final notifier = VolumeNotifier(_MemoryStore());
    await _flush();
    await notifier.set(0.6);

    await notifier.toggleMute();
    expect(notifier.state, 0.0);

    await notifier.toggleMute();
    expect(notifier.state, 0.6);
  });

  test('une valeur sauvee hors bornes est ramenee dans [0, 1]', () async {
    final notifier = VolumeNotifier(_MemoryStore(7));
    await _flush();
    expect(notifier.state, 1.0);
  });

  test('un stockage en panne ne bloque pas le reglage', () async {
    final store = _MemoryStore()..fail = true;
    final notifier = VolumeNotifier(store);
    await _flush();
    expect(notifier.state, AppConstants.defaultVolume);

    await notifier.set(0.2);
    expect(notifier.state, 0.2);
  });

  test('SharedPrefsVolumeStore persiste et relit le volume', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPrefsVolumeStore();
    expect(await store.load(), isNull);

    await store.save(0.42);
    expect(await store.load(), 0.42);
  });

  test('volumeProvider construit un VolumeNotifier branche sur le store reel', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(volumeProvider.notifier), isA<VolumeNotifier>());
    expect(container.read(volumeProvider), AppConstants.defaultVolume);
  });
}
