import 'package:flutter/material.dart';
import '../../favorites/presentation/my_collection_screen.dart';
import '../../explore/presentation/explore_screen.dart';
import '../../search/presentation/search_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../player/presentation/mini_player_widget.dart';
import '../../dlna/data/dlna_manager.dart';
import '../../../core/theme/app_colors.dart';

import '../../player/data/player_manager.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    MyCollectionScreen(),
    ExploreScreen(),
    SearchScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // 앱 시작 시 주변 DLNA 스피커 자동 검색 및 목록 구성
    DlnaManager.instance.discoverDevices();

    PlayerManager.instance.errorNotifier.addListener(_showPlayerError);
  }

  void _showPlayerError() {
    final error = PlayerManager.instance.errorNotifier.value;
    if (error == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(error.message),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 4),
      ));
  }

  @override
  void dispose() {
    PlayerManager.instance.errorNotifier.removeListener(_showPlayerError);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayerWidget(autoStartDiscovery: false),
          BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) => setState(() => _currentIndex = index),
            type: BottomNavigationBarType.fixed,
            backgroundColor: AppColors.surfaceCard,
            selectedItemColor: AppColors.cyanAccent,
            unselectedItemColor: AppColors.textSecondary,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.favorite),
                label: '즐겨찾기',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.explore),
                label: '추천',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.search),
                label: '검색',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.settings),
                label: '설정',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
