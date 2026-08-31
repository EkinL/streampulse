import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class ThemeModeStore {
  Future<ThemeMode?> load();
  Future<void> save(ThemeMode mode);
}

class SharedPrefsThemeModeStore implements ThemeModeStore {
  static const _key = 'theme_mode';

  @override
  Future<ThemeMode?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    return ThemeMode.values.firstWhere(
      (m) => m.name == value,
      orElse: () => ThemeMode.system,
    );
  }

  @override
  Future<void> save(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}

final themeModeStoreProvider = Provider<ThemeModeStore>((ref) {
  return SharedPrefsThemeModeStore();
});

/// Préférence d'apparence (système / clair / sombre), modifiable depuis
/// l'écran "Mon compte" et persistée entre les sessions.
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  final ThemeModeStore _store;

  ThemeModeNotifier(this._store) : super(ThemeMode.system) {
    _restore();
  }

  Future<void> _restore() async {
    try {
      final saved = await _store.load();
      if (saved != null && mounted) state = saved;
    } catch (_) {
      // prefs indisponibles : on garde le defaut (système)
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    try {
      await _store.save(mode);
    } catch (_) {
      // non bloquant
    }
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier(ref.watch(themeModeStoreProvider));
});
