import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

class HumanThemeOption {
  final String id;
  final String name;
  final String description;
  final Color primaryColor;
  final Color secondaryColor;
  final Color previewBackground;
  final IconData icon;

  const HumanThemeOption({
    required this.id,
    required this.name,
    required this.description,
    required this.primaryColor,
    required this.secondaryColor,
    required this.previewBackground,
    required this.icon,
  });
}

class AppTheme {
  static const List<HumanThemeOption> availableThemes = [
    HumanThemeOption(
      id: AppConstants.themeClassicWarm,
      name: 'Bibliothèque Classique & Papier',
      description: 'Teintes ambrées chaleureuses, ivoire doux et esprit reliure artisanale.',
      primaryColor: Color(0xFF8D4925),
      secondaryColor: Color(0xFFD97706),
      previewBackground: Color(0xFFFAF7F2),
      icon: Icons.menu_book_rounded,
    ),
    HumanThemeOption(
      id: AppConstants.themeSageNature,
      name: 'Sauge & Lin Apaisant',
      description: 'Vert sauge végétal et tons lin reposants pour une lecture sereine.',
      primaryColor: Color(0xFF2E5A44),
      secondaryColor: Color(0xFF5B8A68),
      previewBackground: Color(0xFFF4F7F4),
      icon: Icons.eco_rounded,
    ),
    HumanThemeOption(
      id: AppConstants.themeCoffeeLatte,
      name: 'Café & Terre d\'Ocre',
      description: 'Nuances de café chaud, cannelle et papier vélin réconfortant.',
      primaryColor: Color(0xFF5D4037),
      secondaryColor: Color(0xFF8D6E63),
      previewBackground: Color(0xFFFBF8F5),
      icon: Icons.coffee_rounded,
    ),
    HumanThemeOption(
      id: AppConstants.themeOceanBlue,
      name: 'Bleu Nuit & Indigo',
      description: 'Élégance moderne, bleu nuit académique et touches azur.',
      primaryColor: Color(0xFF1E3A8A),
      secondaryColor: Color(0xFF0D9488),
      previewBackground: Color(0xFFF8FAFC),
      icon: Icons.auto_stories_rounded,
    ),
    HumanThemeOption(
      id: AppConstants.themeVelvetDark,
      name: 'Nuit Velours & Ambre (Sombre)',
      description: 'Fond ébène chaud protecteur des yeux avec touches dorées lumineuses.',
      primaryColor: Color(0xFFF59E0B),
      secondaryColor: Color(0xFFE09F67),
      previewBackground: Color(0xFF171513),
      icon: Icons.nightlight_round,
    ),
  ];

  static ThemeData getThemeData(String themeId) {
    switch (themeId) {
      case AppConstants.themeSageNature:
        return _buildTheme(
          primary: const Color(0xFF2E5A44),
          secondary: const Color(0xFF5B8A68),
          background: const Color(0xFFF4F7F4),
          surface: Colors.white,
          cardBorder: const Color(0xFFE3ECE4),
          textPrimary: const Color(0xFF1A2E22),
          isDark: false,
        );
      case AppConstants.themeCoffeeLatte:
        return _buildTheme(
          primary: const Color(0xFF5D4037),
          secondary: const Color(0xFF8D6E63),
          background: const Color(0xFFFBF8F5),
          surface: Colors.white,
          cardBorder: const Color(0xFFEFE7E0),
          textPrimary: const Color(0xFF2D1E18),
          isDark: false,
        );
      case AppConstants.themeOceanBlue:
        return _buildTheme(
          primary: const Color(0xFF1E3A8A),
          secondary: const Color(0xFF0D9488),
          background: const Color(0xFFF8FAFC),
          surface: Colors.white,
          cardBorder: const Color(0xFFE2E8F0),
          textPrimary: const Color(0xFF0F172A),
          isDark: false,
        );
      case AppConstants.themeVelvetDark:
        return _buildTheme(
          primary: const Color(0xFFF59E0B),
          secondary: const Color(0xFFE09F67),
          background: const Color(0xFF171513),
          surface: const Color(0xFF221F1C),
          cardBorder: const Color(0xFF332D27),
          textPrimary: const Color(0xFFF7F4EF),
          isDark: true,
        );
      case AppConstants.themeClassicWarm:
      default:
        return _buildTheme(
          primary: const Color(0xFF8D4925),
          secondary: const Color(0xFFD97706),
          background: const Color(0xFFFAF7F2),
          surface: Colors.white,
          cardBorder: const Color(0xFFEFE8DD),
          textPrimary: const Color(0xFF2C1810),
          isDark: false,
        );
    }
  }

  static ThemeData _buildTheme({
    required Color primary,
    required Color secondary,
    required Color background,
    required Color surface,
    required Color cardBorder,
    required Color textPrimary,
    required bool isDark,
  }) {
    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: primary,
        secondary: secondary,
        surface: surface,
      ),
      scaffoldBackgroundColor: background,
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0.5,
        shadowColor: isDark ? Colors.black38 : const Color(0x10000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cardBorder, width: 1),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 19,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: isDark ? Colors.black87 : Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  // Fallbacks rétro-compatibles
  static ThemeData lightTheme = getThemeData(AppConstants.themeClassicWarm);
  static ThemeData darkTheme = getThemeData(AppConstants.themeVelvetDark);
  static const Color primaryColor = Color(0xFF8D4925);
  static const Color accentColor = Color(0xFFD97706);
}
