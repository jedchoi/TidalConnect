import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      cardColor: AppColors.surfaceCard,
      colorScheme: const ColorScheme.dark(
        surface: AppColors.surfaceCard,
        primary: AppColors.cyanAccent,
        onSurface: AppColors.textPrimary,
      ),
      textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
    );
  }
}
