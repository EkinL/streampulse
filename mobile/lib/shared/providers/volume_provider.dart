import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/constants.dart';

abstract class VolumeStore {
  Future<double?> load();
  Future<void> save(double volume);
}

class SharedPrefsVolumeStore implements VolumeStore {
  static const _key = 'player_volume';

  @override
  Future<double?> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_key);
  }

  @override
  Future<void> save(double volume) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_key, volume);
  }
}

final volumeStoreProvider = Provider<VolumeStore>((ref) {
  return SharedPrefsVolumeStore();
});

/// Volume global [0, 1], suivi par le lecteur de pistes et le lecteur live.
class VolumeNotifier extends StateNotifier<double> {
  final VolumeStore _store;
  double _lastAudible = AppConstants.defaultVolume;

  VolumeNotifier(this._store) : super(AppConstants.defaultVolume) {
    _restore();
  }

  Future<void> _restore() async {
    try {
      final saved = await _store.load();
      if (saved != null && mounted) {
        state = saved.clamp(0.0, 1.0);
        if (state > 0) _lastAudible = state;
      }
    } catch (_) {
      // prefs indisponibles : on garde le defaut
    }
  }

  bool get isMuted => state == 0;

  Future<void> set(double volume) async {
    final clamped = volume.clamp(0.0, 1.0);
    if (clamped > 0) _lastAudible = clamped;
    state = clamped;
    try {
      await _store.save(clamped);
    } catch (_) {
      // non bloquant
    }
  }

  Future<void> toggleMute() => set(isMuted ? _lastAudible : 0);
}

final volumeProvider = StateNotifierProvider<VolumeNotifier, double>((ref) {
  return VolumeNotifier(ref.watch(volumeStoreProvider));
});
