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

abstract class HighContrastStore {
  Future<bool?> load();
  Future<void> save(bool enabled);
}

class SharedPrefsHighContrastStore implements HighContrastStore {
  static const _key = 'high_contrast_enabled';

  @override
  Future<bool?> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key);
  }

  @override
  Future<void> save(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
  }
}

final highContrastStoreProvider = Provider<HighContrastStore>((ref) {
  return SharedPrefsHighContrastStore();
});

/// Préférence "contraste élevé" (accessibilité), indépendante du choix
/// clair/sombre — voir [SPColors.darkHighContrast] et [SPColors.lightHighContrast].
class HighContrastNotifier extends StateNotifier<bool> {
  final HighContrastStore _store;

  HighContrastNotifier(this._store) : super(false) {
    _restore();
  }

  Future<void> _restore() async {
    try {
      final saved = await _store.load();
      if (saved != null && mounted) state = saved;
    } catch (_) {
      // prefs indisponibles : on garde le defaut (desactive)
    }
  }

  Future<void> set(bool enabled) async {
    state = enabled;
    try {
      await _store.save(enabled);
    } catch (_) {
      // non bloquant
    }
  }
}

final highContrastProvider = StateNotifierProvider<HighContrastNotifier, bool>((ref) {
  return HighContrastNotifier(ref.watch(highContrastStoreProvider));
});

/// Taille de texte de l'app, indépendante du réglage système (mais
/// combinable avec [AppTextScale.system], qui laisse l'OS décider).
enum AppTextScale {
  system,
  normal,
  large,
  extraLarge;

  /// Facteur multiplicateur appliqué au [TextScaler] de la MediaQuery.
  /// `null` pour [system] : on ne touche pas au réglage de l'appareil.
  double? get factor => switch (this) {
        AppTextScale.system => null,
        AppTextScale.normal => 1.0,
        AppTextScale.large => 1.15,
        AppTextScale.extraLarge => 1.3,
      };

  String get label => switch (this) {
        AppTextScale.system => 'Système',
        AppTextScale.normal => 'Normal',
        AppTextScale.large => 'Grand',
        AppTextScale.extraLarge => 'Très grand',
      };
}

abstract class TextScaleStore {
  Future<AppTextScale?> load();
  Future<void> save(AppTextScale scale);
}

class SharedPrefsTextScaleStore implements TextScaleStore {
  static const _key = 'text_scale';

  @override
  Future<AppTextScale?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    return AppTextScale.values.firstWhere(
      (s) => s.name == value,
      orElse: () => AppTextScale.system,
    );
  }

  @override
  Future<void> save(AppTextScale scale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, scale.name);
  }
}

final textScaleStoreProvider = Provider<TextScaleStore>((ref) {
  return SharedPrefsTextScaleStore();
});

/// Préférence "grande taille de texte" (accessibilité), modifiable depuis
/// l'écran "Mon compte" et persistée entre les sessions.
class TextScaleNotifier extends StateNotifier<AppTextScale> {
  final TextScaleStore _store;

  TextScaleNotifier(this._store) : super(AppTextScale.system) {
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

  Future<void> set(AppTextScale scale) async {
    state = scale;
    try {
      await _store.save(scale);
    } catch (_) {
      // non bloquant
    }
  }
}

final textScaleProvider = StateNotifierProvider<TextScaleNotifier, AppTextScale>((ref) {
  return TextScaleNotifier(ref.watch(textScaleStoreProvider));
});
