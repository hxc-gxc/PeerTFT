import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palette and shapes extracted from the PeerTFT mockups (see
/// design-d-application-transfert/mockups/): cream background, indigo/pink/
/// mint accents, heavily rounded cards and buttons, bold rounded headline
/// font (Baloo 2).
abstract final class AppTheme {
  // Mockup palette: warm cream, vibrant electric violet, coral pink, fresh mint
  static const background = Color(0xFFFAF7F2);
  static const indigo = Color(0xFF582BE8);
  static const purpleEnd = Color(0xFF8B5CF6);
  static const pink = Color(0xFFFF6B8B);
  static const peach = Color(0xFFFFA5A5);
  static const mint = Color(0xFF4EEDB2);
  static const mintLight = Color(0xFFD1FAE5);
  static const ink = Color(0xFF18181B);

  static const radius = 24.0;
  static const cardRadius = 28.0;

  static ThemeData get theme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: indigo,
      brightness: Brightness.light,
      primary: indigo,
      secondary: pink,
      tertiary: mint,
      surface: Colors.white,
    );

    final headlineFont = GoogleFonts.baloo2TextTheme();
    final textTheme = headlineFont.copyWith(
      headlineLarge: GoogleFonts.baloo2(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: ink,
        height: 1.1,
      ),
      headlineMedium: GoogleFonts.baloo2(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: ink,
        height: 1.15,
      ),
      headlineSmall: GoogleFonts.baloo2(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      titleLarge: GoogleFonts.baloo2(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      titleMedium: GoogleFonts.baloo2(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      bodyLarge: GoogleFonts.nunito(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      bodyMedium: GoogleFonts.nunito(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      bodySmall: GoogleFonts.nunito(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: ink.withValues(alpha: 0.6),
      ),
      labelLarge: GoogleFonts.baloo2(fontSize: 16, fontWeight: FontWeight.w700),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      textTheme: textTheme.apply(bodyColor: ink, displayColor: ink),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: ink,
        centerTitle: false,
        titleTextStyle: GoogleFonts.baloo2(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: ink,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: indigo,
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: indigo.withValues(alpha: 0.35),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(cardRadius),
          ),
          textStyle: GoogleFonts.baloo2(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(cardRadius),
          ),
          side: const BorderSide(color: mint, width: 2),
          foregroundColor: mint,
          textStyle: GoogleFonts.baloo2(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: indigo,
          textStyle: GoogleFonts.baloo2(fontWeight: FontWeight.w700),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          borderSide: const BorderSide(color: mint, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          borderSide: const BorderSide(color: mint, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          borderSide: const BorderSide(color: indigo, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: indigo,
        linearTrackColor: indigo.withValues(alpha: 0.15),
      ),
    );
  }
}
