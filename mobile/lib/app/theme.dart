import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens extracted from Figma — StreamPulse dark theme.
class SP {
  SP._();

  // Core backgrounds
  static const Color bg = Color(0xFF0F0F23);
  static const Color surface = Color(0xFF1A1A2E);
  static const Color surfaceVariant = Color(0xFF28283D);
  static const Color tag = Color(0xFF333348);

  // Text hierarchy
  static const Color text1 = Color(0xFFE2E0FC);
  static const Color text2 = Color(0xFFC7C4D8);
  static const Color text3 = Color(0xFF918FA1);

  // Accent
  static const Color accent = Color(0xFFC4C0FF);
  static const Color gradStart = Color(0xFFC4C0FF);
  static const Color gradEnd = Color(0xFF8781FF);
  static const Color btnText = Color(0xFF1B0091);

  // Status
  static const Color liveBg = Color(0xFFFFB4A8);
  static const Color liveText = Color(0xFF690100);
  static const Color offlineBg = Color(0x4D464555);
  static const Color error = Color(0xFFEF5350);

  // Misc
  static const Color divider = Color(0x33464555);
  static const Color glow = Color(0x26C4C0FF);
  static const Color navBg = Color(0xB31A1A2E);
  static const Color navShadow = Color(0x146C63FF);

  static const Gradient primaryGradient = LinearGradient(
    begin: Alignment(-0.3, -1),
    end: Alignment(0.3, 1),
    colors: [gradStart, gradEnd],
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: SP.bg,
      colorScheme: const ColorScheme.dark(
        primary: SP.accent,
        onPrimary: SP.btnText,
        secondary: SP.gradEnd,
        surface: SP.surface,
        onSurface: SP.text1,
        error: SP.error,
        outline: SP.divider,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).copyWith(
        headlineLarge: GoogleFonts.inter(fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: -1.8, color: SP.text1),
        headlineMedium: GoogleFonts.inter(fontSize: 30, fontWeight: FontWeight.w900, color: SP.text1),
        headlineSmall: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: SP.text1),
        titleLarge: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: SP.text1),
        titleMedium: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: SP.text1),
        titleSmall: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: SP.text1),
        bodyLarge: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w400, color: SP.text2),
        bodyMedium: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400, color: SP.text2),
        bodySmall: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w400, color: SP.text2),
        labelLarge: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: SP.text2),
        labelSmall: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: 0.5, color: SP.text2),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: SP.surface,
        foregroundColor: SP.text1,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: SP.text1),
      ),
      cardTheme: CardThemeData(
        color: SP.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SP.surface,
        hintStyle: GoogleFonts.inter(fontSize: 16, color: SP.text3),
        labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: SP.text2),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: SP.accent, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: SP.error)),
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
            color: selected ? SP.accent : SP.text2.withValues(alpha: 0.6),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? SP.accent : SP.text2.withValues(alpha: 0.6), size: 22);
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: SP.surface,
        contentTextStyle: GoogleFonts.inter(color: SP.text1),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dividerColor: SP.divider,
      chipTheme: ChipThemeData(
        backgroundColor: SP.surfaceVariant,
        labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: SP.text1),
        shape: const StadiumBorder(),
        side: BorderSide.none,
      ),
    );
  }

  static ThemeData get lightTheme => darkTheme;
}
