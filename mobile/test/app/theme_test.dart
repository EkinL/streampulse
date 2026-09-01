import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/app/theme.dart';

void main() {
  group('SPColors', () {
    test('copyWith remplace uniquement les champs fournis', () {
      const base = SPColors.dark;
      final copy = base.copyWith(bg: Colors.red, text1: Colors.blue);

      expect(copy.bg, Colors.red);
      expect(copy.text1, Colors.blue);
      // Le reste des champs vient de l'instance d'origine.
      expect(copy.altBg, base.altBg);
      expect(copy.surface, base.surface);
      expect(copy.surfaceVariant, base.surfaceVariant);
      expect(copy.tag, base.tag);
      expect(copy.text2, base.text2);
      expect(copy.text3, base.text3);
      expect(copy.textMuted, base.textMuted);
      expect(copy.accent, base.accent);
      expect(copy.onAccent, base.onAccent);
      expect(copy.offlineBg, base.offlineBg);
      expect(copy.error, base.error);
      expect(copy.success, base.success);
      expect(copy.dangerText, base.dangerText);
      expect(copy.divider, base.divider);
      expect(copy.consoleCardBorder, base.consoleCardBorder);
      expect(copy.glow, base.glow);
      expect(copy.navBg, base.navBg);
      expect(copy.navShadow, base.navShadow);
    });

    test('copyWith sans argument renvoie les memes valeurs', () {
      const base = SPColors.light;
      final copy = base.copyWith();

      expect(copy.bg, base.bg);
      expect(copy.accent, base.accent);
      expect(copy.navShadow, base.navShadow);
    });

    test('lerp a t=0 renvoie les couleurs de depart, a t=1 celles d\'arrivee', () {
      const dark = SPColors.dark;
      const light = SPColors.light;

      final start = dark.lerp(light, 0);
      final end = dark.lerp(light, 1);

      expect(start.bg, dark.bg);
      expect(start.accent, dark.accent);
      expect(end.bg, light.bg);
      expect(end.accent, light.accent);
    });

    test('lerp a mi-chemin melange les deux thèmes', () {
      const dark = SPColors.dark;
      const light = SPColors.light;

      final mid = dark.lerp(light, 0.5);

      expect(mid.bg, Color.lerp(dark.bg, light.bg, 0.5));
      expect(mid.text1, Color.lerp(dark.text1, light.text1, 0.5));
      expect(mid.navShadow, Color.lerp(dark.navShadow, light.navShadow, 0.5));
    });

    test('lerp renvoie l\'instance courante si l\'autre extension n\'est pas SPColors', () {
      const dark = SPColors.dark;

      final result = dark.lerp(null, 0.5);

      expect(result, same(dark));
    });
  });

  group('SPColorsX', () {
    testWidgets('context.colors expose l\'extension du theme courant', (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(builder: (context) {
            capturedContext = context;
            return const SizedBox();
          }),
        ),
      );

      expect(capturedContext.colors.bg, SPColors.dark.bg);
    });
  });

  group('AppTheme', () {
    test('darkTheme et lightTheme portent la bonne extension SPColors', () {
      expect(AppTheme.darkTheme.extension<SPColors>(), SPColors.dark);
      expect(AppTheme.lightTheme.extension<SPColors>(), SPColors.light);
      expect(AppTheme.darkTheme.brightness, Brightness.dark);
      expect(AppTheme.lightTheme.brightness, Brightness.light);
    });

    test('darkHighContrastTheme et lightHighContrastTheme portent les palettes AAA', () {
      expect(AppTheme.darkHighContrastTheme.extension<SPColors>(), SPColors.darkHighContrast);
      expect(AppTheme.lightHighContrastTheme.extension<SPColors>(), SPColors.lightHighContrast);
      expect(AppTheme.darkHighContrastTheme.brightness, Brightness.dark);
      expect(AppTheme.lightHighContrastTheme.brightness, Brightness.light);
    });
  });
}
