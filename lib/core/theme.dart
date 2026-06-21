/// Theme configuration for WiFi voice room application.
///
/// Dark, premium aesthetic with blue gradient accents,
/// glassmorphism effects, and modern typography.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'constants.dart';

class WifiTheme {
  WifiTheme._();

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: kDarkBackground,
      colorScheme: const ColorScheme.dark(
        primary: kPrimaryBlue,
        secondary: kAccentGlow,
        surface: kCardBackground,
        error: kErrorRed,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: Colors.white,
        onError: Colors.white,
      ),
      textTheme: _textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: kPrimaryBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
          textStyle: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: kPrimaryBlue,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          side: const BorderSide(color: kBorderColor),
          textStyle: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: kSurfaceColor,
        hintStyle: GoogleFonts.inter(color: kMutedText),
        labelStyle: GoogleFonts.inter(color: kMutedText),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kBorderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kBorderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kPrimaryBlue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kErrorRed),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
      cardTheme: CardThemeData(
        color: kCardBackground,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: kBorderColor, width: 0.5),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: kSurfaceColor,
        contentTextStyle: GoogleFonts.inter(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static TextTheme get _textTheme {
    return TextTheme(
      displayLarge: GoogleFonts.outfit(
        fontSize: 48,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        letterSpacing: -1,
      ),
      displayMedium: GoogleFonts.outfit(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        letterSpacing: -0.5,
      ),
      displaySmall: GoogleFonts.outfit(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      headlineMedium: GoogleFonts.outfit(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      headlineSmall: GoogleFonts.outfit(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      titleLarge: GoogleFonts.outfit(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: Colors.white,
      ),
      titleSmall: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Colors.white,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: Colors.white,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: Colors.white,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: kMutedText,
      ),
      labelLarge: GoogleFonts.outfit(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Colors.white,
        letterSpacing: 0.5,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: kMutedText,
        letterSpacing: 0.5,
      ),
    );
  }
}

/// Glassmorphism container decoration.
BoxDecoration glassDecoration({
  double borderRadius = 16,
  double opacity = 0.1,
  Color? borderColor,
}) {
  return BoxDecoration(
    color: Colors.white.withValues(alpha: opacity),
    borderRadius: BorderRadius.circular(borderRadius),
    border: Border.all(
      color: borderColor ?? Colors.white.withValues(alpha: 0.1),
      width: 0.5,
    ),
  );
}
