import 'package:flutter/material.dart';

import 'screens/collection_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'services/storage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DWatchLabApp());
}

const gold = Color(0xFFC9A961);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: gold,
    brightness: Brightness.dark,
  ).copyWith(
    primary: gold,
    onPrimary: const Color(0xFF1A1508),
    surface: const Color(0xFF111214),
    surfaceContainerLowest: const Color(0xFF0B0C0D),
    surfaceContainerLow: const Color(0xFF16171A),
    surfaceContainer: const Color(0xFF1B1C20),
    surfaceContainerHigh: const Color(0xFF222328),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: const TextStyle(
          fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: 0.3),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      ),
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      showCloseIcon: true,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

class DWatchLabApp extends StatelessWidget {
  const DWatchLabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'D. Watch Lab',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final storage = Storage();
  final hasKey = ValueNotifier<bool>(true);
  int index = 0;
  int collectionVersion = 0;

  @override
  void initState() {
    super.initState();
    storage.loadSettings().then((s) {
      if (mounted) hasKey.value = s.apiKey.trim().isNotEmpty;
    });
  }

  void _onSaved() => setState(() => collectionVersion++);

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        storage: storage,
        hasKey: hasKey,
        onSaved: _onSaved,
        collectionVersion: collectionVersion,
      ),
      CollectionScreen(
          key: ValueKey(collectionVersion),
          storage: storage,
          onChanged: _onSaved),
      ValueListenableBuilder<bool>(
        valueListenable: hasKey,
        builder: (_, k, __) => SettingsScreen(
          key: ValueKey(k),
          storage: storage,
          onKeyChanged: (v) => hasKey.value = v,
        ),
      ),
    ];
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.photo_camera_outlined),
              selectedIcon: Icon(Icons.photo_camera),
              label: 'Valuta'),
          NavigationDestination(
              icon: Icon(Icons.watch_outlined),
              selectedIcon: Icon(Icons.watch),
              label: 'Collezione'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Impostazioni'),
        ],
      ),
    );
  }
}
