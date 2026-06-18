import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const bg = Color(0xFF080B14);
  static const surface = Color(0xFF0D1120);
  static const card = Color(0xFF111627);
  static const cardRaised = Color(0xFF161C2E);
  static const border = Color(0x11FFFFFF);
  static const gold = Color(0xFFC9A84C);
  static const goldBright = Color(0xFFF0C040);
  static const goldDim = Color(0x26C9A84C);
  static const blue = Color(0xFF2563EB);
  static const green = Color(0xFF10B981);
  static const greenDim = Color(0x1F10B981);
  static const orange = Color(0xFFF59E0B);
  static const orangeDim = Color(0x1FF59E0B);
  static const red = Color(0xFFEF4444);
  static const redDim = Color(0x1FEF4444);
  static const text = Color(0xFFF1F3F9);
  static const text2 = Color(0xFF9AA5BE);
  static const text3 = Color(0xFF5A6478);
}

class AppTheme {
  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.gold,
        secondary: AppColors.blue,
        surface: AppColors.surface,
        error: AppColors.red,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).copyWith(
        displayLarge: GoogleFonts.inter(
          fontSize: 32, fontWeight: FontWeight.w900,
          color: AppColors.text, letterSpacing: -1,
        ),
        titleLarge: GoogleFonts.inter(
          fontSize: 18, fontWeight: FontWeight.w800,
          color: AppColors.text, letterSpacing: -0.3,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 15, fontWeight: FontWeight.w700,
          color: AppColors.text,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 13, fontWeight: FontWeight.w400,
          color: AppColors.text2,
        ),
        labelSmall: GoogleFonts.inter(
          fontSize: 10, fontWeight: FontWeight.w700,
          letterSpacing: 1.2, color: AppColors.text3,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 16, fontWeight: FontWeight.w800,
          color: AppColors.text,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.gold,
        unselectedItemColor: AppColors.text3,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cardRaised,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.gold),
        ),
      ),
      dividerColor: AppColors.border,
      dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
    );
  }
}
