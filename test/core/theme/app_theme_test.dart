import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tidal_connect_lite/core/theme/app_colors.dart';
import 'package:tidal_connect_lite/core/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Dark Elegant Tidal Theme Tokens', () {
    test('AppColors provides exact design token hex values', () {
      expect(AppColors.background, const Color(0xFF121212));
      expect(AppColors.surfaceCard, const Color(0xFF1E1E2E));
      expect(AppColors.surfaceLight, const Color(0xFF2A2A3D));
      expect(AppColors.cyanAccent, const Color(0xFF00C4B4));
      expect(AppColors.textPrimary, Colors.white);
      expect(AppColors.textSecondary, const Color(0xFFA0A0B0));
    });

    test('AppTheme should provide correct dark theme palette and configuration', () {
      final theme = AppTheme.darkTheme;
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, AppColors.background);
      expect(theme.cardColor, AppColors.surfaceCard);
      expect(theme.colorScheme.background, AppColors.background);
      expect(theme.colorScheme.surface, AppColors.surfaceCard);
      expect(theme.colorScheme.primary, AppColors.cyanAccent);
      expect(theme.colorScheme.onBackground, AppColors.textPrimary);
      expect(theme.colorScheme.onSurface, AppColors.textPrimary);
      expect(theme.textTheme, isNotNull);
    });
  });
}
