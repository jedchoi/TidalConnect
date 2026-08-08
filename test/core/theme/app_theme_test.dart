import 'package:flutter_test/flutter_test.dart';
import 'package:tidal_connect_lite/core/theme/app_colors.dart';
import 'package:tidal_connect_lite/core/theme/app_theme.dart';

void main() {
  test('AppTheme should provide correct dark theme palette', () {
    final theme = AppTheme.darkTheme;
    expect(theme.scaffoldBackgroundColor, AppColors.background);
    expect(theme.colorScheme.primary, AppColors.cyanAccent);
    expect(theme.colorScheme.surface, AppColors.surfaceCard);
  });
}
