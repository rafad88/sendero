import 'package:flutter/material.dart';

abstract final class AppColors {
  static const forestGreen = Color(0xFF2D6A4F);
  static const trailOrange = Color(0xFFF4845F);
  static const parchment   = Color(0xFFF8F4EF);
  static const darkSurface = Color(0xFF1A1A2E);
  static const elevLow     = Color(0xFFD4A373);
  static const elevHigh    = Color(0xFF6D6875);
}

abstract final class AppTheme {
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.forestGreen,
      brightness: Brightness.light,
      surface: AppColors.parchment,
    ),
    scaffoldBackgroundColor: AppColors.parchment,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.forestGreen,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.trailOrange,
      foregroundColor: Colors.white,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.forestGreen,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.forestGreen,
      brightness: Brightness.dark,
      surface: AppColors.darkSurface,
    ),
    scaffoldBackgroundColor: AppColors.darkSurface,
    appBarTheme: const AppBarTheme(elevation: 0),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.trailOrange,
      foregroundColor: Colors.white,
    ),
  );
}
