import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streampulse/shared/providers/theme_provider.dart';

class _FakeThemeModeStore implements ThemeModeStore {
  ThemeMode? saved;
  Object? loadError;
  Object? saveError;

  @override
  Future<ThemeMode?> load() async {
    if (loadError != null) throw loadError!;
    return saved;
  }

  @override
  Future<void> save(ThemeMode mode) async {
    if (saveError != null) throw saveError!;
    saved = mode;
  }
}

class _FakeHighContrastStore implements HighContrastStore {
  bool? saved;
  Object? loadError;
  Object? saveError;

  @override
  Future<bool?> load() async {
    if (loadError != null) throw loadError!;
    return saved;
  }

  @override
  Future<void> save(bool enabled) async {
    if (saveError != null) throw saveError!;
    saved = enabled;
  }
}

class _FakeTextScaleStore implements TextScaleStore {
  AppTextScale? saved;
  Object? loadError;
  Object? saveError;

  @override
  Future<AppTextScale?> load() async {
    if (loadError != null) throw loadError!;
    return saved;
  }

  @override
  Future<void> save(AppTextScale scale) async {
    if (saveError != null) throw saveError!;
    saved = scale;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeModeNotifier', () {
    test('demarre sur system puis restaure la valeur sauvegardee', () async {
      final store = _FakeThemeModeStore()..saved = ThemeMode.dark;
      final notifier = ThemeModeNotifier(store);

      expect(notifier.state, ThemeMode.system);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state, ThemeMode.dark);
    });

    test('garde system si le store ne renvoie rien', () async {
      final notifier = ThemeModeNotifier(_FakeThemeModeStore());
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state, ThemeMode.system);
    });

    test('garde system si le chargement echoue', () async {
      final store = _FakeThemeModeStore()..loadError = Exception('boom');
      final notifier = ThemeModeNotifier(store);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state, ThemeMode.system);
    });

    test('set met a jour le state et persiste', () async {
      final store = _FakeThemeModeStore();
      final notifier = ThemeModeNotifier(store);
      await Future<void>.delayed(Duration.zero);

      await notifier.set(ThemeMode.light);

      expect(notifier.state, ThemeMode.light);
      expect(store.saved, ThemeMode.light);
    });

    test('set met a jour le state meme si la sauvegarde echoue', () async {
      final store = _FakeThemeModeStore()..saveError = Exception('boom');
      final notifier = ThemeModeNotifier(store);
      await Future<void>.delayed(Duration.zero);

      await notifier.set(ThemeMode.dark);

      expect(notifier.state, ThemeMode.dark);
    });
  });

  group('HighContrastNotifier', () {
    test('demarre desactive puis restaure la valeur sauvegardee', () async {
      final store = _FakeHighContrastStore()..saved = true;
      final notifier = HighContrastNotifier(store);

      expect(notifier.state, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state, isTrue);
    });

    test('garde desactive si le chargement echoue', () async {
      final store = _FakeHighContrastStore()..loadError = Exception('boom');
      final notifier = HighContrastNotifier(store);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state, isFalse);
    });

    test('set met a jour le state et persiste', () async {
      final store = _FakeHighContrastStore();
      final notifier = HighContrastNotifier(store);
      await Future<void>.delayed(Duration.zero);

      await notifier.set(true);

      expect(notifier.state, isTrue);
      expect(store.saved, isTrue);
    });

    test('set met a jour le state meme si la sauvegarde echoue', () async {
      final store = _FakeHighContrastStore()..saveError = Exception('boom');
      final notifier = HighContrastNotifier(store);
      await Future<void>.delayed(Duration.zero);

      await notifier.set(true);

      expect(notifier.state, isTrue);
    });
  });

  group('TextScaleNotifier', () {
    test('demarre sur system puis restaure la valeur sauvegardee', () async {
      final store = _FakeTextScaleStore()..saved = AppTextScale.large;
      final notifier = TextScaleNotifier(store);

      expect(notifier.state, AppTextScale.system);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state, AppTextScale.large);
    });

    test('garde system si le chargement echoue', () async {
      final store = _FakeTextScaleStore()..loadError = Exception('boom');
      final notifier = TextScaleNotifier(store);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state, AppTextScale.system);
    });

    test('set met a jour le state et persiste', () async {
      final store = _FakeTextScaleStore();
      final notifier = TextScaleNotifier(store);
      await Future<void>.delayed(Duration.zero);

      await notifier.set(AppTextScale.extraLarge);

      expect(notifier.state, AppTextScale.extraLarge);
      expect(store.saved, AppTextScale.extraLarge);
    });

    test('set met a jour le state meme si la sauvegarde echoue', () async {
      final store = _FakeTextScaleStore()..saveError = Exception('boom');
      final notifier = TextScaleNotifier(store);
      await Future<void>.delayed(Duration.zero);

      await notifier.set(AppTextScale.normal);

      expect(notifier.state, AppTextScale.normal);
    });
  });

  group('AppTextScale', () {
    test('factor renvoie null pour system et les bons multiplicateurs sinon', () {
      expect(AppTextScale.system.factor, isNull);
      expect(AppTextScale.normal.factor, 1.0);
      expect(AppTextScale.large.factor, 1.15);
      expect(AppTextScale.extraLarge.factor, 1.3);
    });

    test('label renvoie un libelle francais pour chaque valeur', () {
      expect(AppTextScale.system.label, 'Système');
      expect(AppTextScale.normal.label, 'Normal');
      expect(AppTextScale.large.label, 'Grand');
      expect(AppTextScale.extraLarge.label, 'Très grand');
    });
  });

  group('Implementations SharedPreferences', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('SharedPrefsThemeModeStore persiste et relit le mode', () async {
      final store = SharedPrefsThemeModeStore();
      expect(await store.load(), ThemeMode.system);

      await store.save(ThemeMode.dark);
      expect(await store.load(), ThemeMode.dark);
    });

    test('SharedPrefsHighContrastStore persiste et relit le booleen', () async {
      final store = SharedPrefsHighContrastStore();
      expect(await store.load(), isNull);

      await store.save(true);
      expect(await store.load(), isTrue);
    });

    test('SharedPrefsTextScaleStore persiste et relit l\'echelle', () async {
      final store = SharedPrefsTextScaleStore();
      expect(await store.load(), AppTextScale.system);

      await store.save(AppTextScale.large);
      expect(await store.load(), AppTextScale.large);
    });
  });
}
