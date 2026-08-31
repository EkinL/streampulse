import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens extracted from Figma — StreamPulse dark theme.
///
/// Brand elements that stay identical in both light and dark mode (the
/// accent gradient used on primary buttons, and the LIVE badge colors) live
/// here as plain constants. Everything that must flip between themes
/// (backgrounds, text, the flat accent color used directly as foreground)
/// lives in [SPColors] instead — see `context.colors`.
class SP {
  SP._();

  // Brand gradient (buttons, logo mark) — same in both themes.
  static const Color gradStart = Color(0xFFC4C0FF);
  static const Color gradEnd = Color(0xFF8781FF);
  static const Color btnText = Color(0xFF1B0091);

  // LIVE badge — same in both themes.
  static const Color liveBg = Color(0xFFFFB4A8);
  static const Color liveText = Color(0xFF690100);

  static const Gradient primaryGradient = LinearGradient(
    begin: Alignment(-0.3, -1),
    end: Alignment(0.3, 1),
    colors: [gradStart, gradEnd],
  );
}

/// Theme-dependent design tokens. Access via `context.colors.xxx` — never
/// hold onto an instance across a theme change, always read it from the
/// current [BuildContext].
@immutable
class SPColors extends ThemeExtension<SPColors> {
  // Backgrounds
  final Color bg;
  final Color altBg;
  final Color surface;
  final Color surfaceVariant;
  final Color tag;

  // Text hierarchy
  final Color text1;
  final Color text2;
  final Color text3;
  final Color textMuted;

  // Accent — flat color used directly as text/icon/background, distinct
  // from the brand gradient in [SP] which stays constant across themes.
  final Color accent;

  /// Foreground color for content placed on top of [accent].
  final Color onAccent;

  // Status
  final Color offlineBg;
  final Color error;
  final Color success;

  /// "Stop broadcasting" label color, distinct from [error] (button fill).
  final Color dangerText;

  // Misc / decorative
  final Color divider;
  final Color consoleCardBorder;
  final Color glow;
  final Color navBg;
  final Color navShadow;

  const SPColors({
    required this.bg,
    required this.altBg,
    required this.surface,
    required this.surfaceVariant,
    required this.tag,
    required this.text1,
    required this.text2,
    required this.text3,
    required this.textMuted,
    required this.accent,
    required this.onAccent,
    required this.offlineBg,
    required this.error,
    required this.success,
    required this.dangerText,
    required this.divider,
    required this.consoleCardBorder,
    required this.glow,
    required this.navBg,
    required this.navShadow,
  });

  static const dark = SPColors(
    bg: Color(0xFF0F0F23),
    altBg: Color(0xFF111125),
    surface: Color(0xFF1A1A2E),
    surfaceVariant: Color(0xFF28283D),
    tag: Color(0xFF333348),
    text1: Color(0xFFE2E0FC),
    text2: Color(0xFFC7C4D8),
    text3: Color(0xFF918FA1),
    // Remplace les usages de `text2.withValues(alpha: 0.6)`, dont le
    // contraste sur fond sombre passait sous le seuil d'accessibilite.
    textMuted: Color(0xFFA9A6BD),
    accent: Color(0xFFC4C0FF),
    onAccent: SP.btnText,
    offlineBg: Color(0x4D464555),
    error: Color(0xFFEF5350),
    success: Color(0xFF81C784),
    dangerText: Color(0xFFFF8A80),
    divider: Color(0x33464555),
    consoleCardBorder: Color(0x17E2E0FC),
    glow: Color(0x26C4C0FF),
    navBg: Color(0xB31A1A2E),
    navShadow: Color(0x146C63FF),
  );

  /// Ratios WCAG (luminance relative) verifies pour chaque paire texte/fond
  /// utilisee dans l'app — voir docs/accessibilite.md. La marge la plus
  /// faible est text3 sur surfaceVariant (~5.4:1), toujours au-dessus du
  /// seuil AA texte normal (4.5:1).
  static const light = SPColors(
    bg: Color(0xFFF7F7FB),
    altBg: Color(0xFFF1F1F8),
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFECECF5),
    tag: Color(0xFFE1E1EE),
    text1: Color(0xFF18172B),
    text2: Color(0xFF454458),
    text3: Color(0xFF5F5E72),
    textMuted: Color(0xFF57566B),
    // Le lavande clair du theme sombre (C4C0FF) n'a pas assez de contraste
    // sur fond clair : indigo plus sature pour rester lisible en texte/icone.
    accent: Color(0xFF5245D1),
    onAccent: Colors.white,
    // Opaque plutot que translucide (contrairement au theme sombre) : un gris
    // translucide sur fond clair n'offre pas assez de contraste au texte.
    offlineBg: Color(0xFFD6D6E4),
    error: Color(0xFFC62828),
    success: Color(0xFF2E7D32),
    dangerText: Color(0xFFB3261E),
    divider: Color(0x33454568),
    consoleCardBorder: Color(0x1718172B),
    glow: Color(0x265245D1),
    navBg: Color(0xB3FFFFFF),
    navShadow: Color(0x146C63FF),
  );

  @override
  SPColors copyWith({
    Color? bg,
    Color? altBg,
    Color? surface,
    Color? surfaceVariant,
    Color? tag,
    Color? text1,
    Color? text2,
    Color? text3,
    Color? textMuted,
    Color? accent,
    Color? onAccent,
    Color? offlineBg,
    Color? error,
    Color? success,
    Color? dangerText,
    Color? divider,
    Color? consoleCardBorder,
    Color? glow,
    Color? navBg,
    Color? navShadow,
  }) {
    return SPColors(
      bg: bg ?? this.bg,
      altBg: altBg ?? this.altBg,
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      tag: tag ?? this.tag,
      text1: text1 ?? this.text1,
      text2: text2 ?? this.text2,
      text3: text3 ?? this.text3,
      textMuted: textMuted ?? this.textMuted,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      offlineBg: offlineBg ?? this.offlineBg,
      error: error ?? this.error,
      success: success ?? this.success,
      dangerText: dangerText ?? this.dangerText,
      divider: divider ?? this.divider,
      consoleCardBorder: consoleCardBorder ?? this.consoleCardBorder,
      glow: glow ?? this.glow,
      navBg: navBg ?? this.navBg,
      navShadow: navShadow ?? this.navShadow,
    );
  }

  @override
  SPColors lerp(ThemeExtension<SPColors>? other, double t) {
    if (other is! SPColors) return this;
    return SPColors(
      bg: Color.lerp(bg, other.bg, t)!,
      altBg: Color.lerp(altBg, other.altBg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      tag: Color.lerp(tag, other.tag, t)!,
      text1: Color.lerp(text1, other.text1, t)!,
      text2: Color.lerp(text2, other.text2, t)!,
      text3: Color.lerp(text3, other.text3, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      offlineBg: Color.lerp(offlineBg, other.offlineBg, t)!,
      error: Color.lerp(error, other.error, t)!,
      success: Color.lerp(success, other.success, t)!,
      dangerText: Color.lerp(dangerText, other.dangerText, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      consoleCardBorder:
          Color.lerp(consoleCardBorder, other.consoleCardBorder, t)!,
      glow: Color.lerp(glow, other.glow, t)!,
      navBg: Color.lerp(navBg, other.navBg, t)!,
      navShadow: Color.lerp(navShadow, other.navShadow, t)!,
    );
  }
}

/// Shorthand for `Theme.of(context).extension<SPColors>()!`.
extension SPColorsX on BuildContext {
  SPColors get colors => Theme.of(this).extension<SPColors>()!;
}

class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme => _buildTheme(SPColors.dark, Brightness.dark);

  static ThemeData get lightTheme => _buildTheme(SPColors.light, Brightness.light);

  static ThemeData _buildTheme(SPColors c, Brightness brightness) {
    final base = brightness == Brightness.dark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: c.bg,
      extensions: [c],
      // Le focus clavier par defaut de Material 3 (overlay ~10% d'opacite)
      // est trop discret sur cette palette custom : on le renforce pour
      // qu'il reste perceptible a la tabulation (WCAG 2.4.7).
      focusColor: c.accent.withValues(alpha: 0.24),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(overlayColor: c.accent),
      ),
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: c.accent,
        onPrimary: c.onAccent,
        secondary: SP.gradEnd,
        onSecondary: SP.btnText,
        surface: c.surface,
        onSurface: c.text1,
        error: c.error,
        onError: c.onAccent,
        outline: c.divider,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        headlineLarge: GoogleFonts.inter(fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: -1.8, color: c.text1),
        headlineMedium: GoogleFonts.inter(fontSize: 30, fontWeight: FontWeight.w900, color: c.text1),
        headlineSmall: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: c.text1),
        titleLarge: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: c.text1),
        titleMedium: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: c.text1),
        titleSmall: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: c.text1),
        bodyLarge: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w400, color: c.text2),
        bodyMedium: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400, color: c.text2),
        bodySmall: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w400, color: c.text2),
        labelLarge: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: c.text2),
        labelSmall: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: 0.5, color: c.text2),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        foregroundColor: c.text1,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: c.text1),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        hintStyle: GoogleFonts.inter(fontSize: 16, color: c.text3),
        labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: c.text2),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.accent, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.error)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 18),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
            color: selected ? c.accent : c.textMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? c.accent : c.textMuted, size: 22);
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surface,
        contentTextStyle: GoogleFonts.inter(color: c.text1),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dividerColor: c.divider,
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceVariant,
        labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: c.text1),
        shape: const StadiumBorder(),
        side: BorderSide.none,
      ),
    );
  }
}
