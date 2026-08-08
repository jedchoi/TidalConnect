import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'features/main/presentation/main_screen.dart';

void main() {
  runApp(
    const ProviderScope(
      child: TidalConnectLiteApp(),
    ),
  );
}

class TidalConnectLiteApp extends StatelessWidget {
  const TidalConnectLiteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tidal Connect Lite',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainScreen(),
    );
  }
}

