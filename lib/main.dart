import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';

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
      home: const Scaffold(
        body: Center(
          child: Text(
            'Tidal Connect Lite 에 오신 것을 환영합니다',
            style: TextStyle(fontSize: 18),
          ),
        ),
      ),
    );
  }
}
