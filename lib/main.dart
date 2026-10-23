import 'package:flutter/material.dart';
import 'core/constants/app_constants.dart';
import 'core/storage/secure_storage_service.dart';
import 'core/theme/app_theme.dart';
import 'features/library/presentation/home_library_screen.dart';
import 'features/onboarding/presentation/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Protection contre tout écran noir en mode release
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFFAF7F2),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.menu_book_rounded, color: Color(0xFF8D4925), size: 64),
                    const SizedBox(height: 16),
                    const Text(
                      'Bibliothèque PDF',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF2C1810)),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Initialisation de la bibliothèque...',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.black87),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        // Relancer sur l'accueil en cas de bug passager
                        main();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8D4925),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Actualiser l\'application'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  };

  bool onboardingDone = false;
  String savedTheme = AppConstants.themeClassicWarm;

  try {
    await SecureStorageService.instance.init();
    onboardingDone = await SecureStorageService.instance.isOnboardingCompleted();
    savedTheme = await SecureStorageService.instance.getSelectedTheme();
  } catch (e, stack) {
    debugPrint('Initialisation sécurisée en mode secours: $e\n$stack');
  }

  runApp(SmartPdfLibraryApp(
    initialReady: onboardingDone,
    initialThemeId: savedTheme,
  ));
}

class SmartPdfLibraryApp extends StatefulWidget {
  final bool initialReady;
  final String initialThemeId;

  const SmartPdfLibraryApp({
    super.key,
    required this.initialReady,
    required this.initialThemeId,
  });

  static _SmartPdfLibraryAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_SmartPdfLibraryAppState>();

  static void updateTheme(BuildContext context, String themeId) {
    of(context)?.updateTheme(themeId);
  }

  @override
  State<SmartPdfLibraryApp> createState() => _SmartPdfLibraryAppState();
}

class _SmartPdfLibraryAppState extends State<SmartPdfLibraryApp> {
  late bool _isReady;
  late String _currentThemeId;

  @override
  void initState() {
    super.initState();
    _isReady = widget.initialReady;
    _currentThemeId = widget.initialThemeId;
  }

  void onOnboardingCompleted() {
    setState(() {
      _isReady = true;
    });
  }

  void updateTheme(String themeId) {
    setState(() {
      _currentThemeId = themeId;
    });
    SecureStorageService.instance.setSelectedTheme(themeId);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.getThemeData(_currentThemeId),
      darkTheme: AppTheme.getThemeData(AppConstants.themeVelvetDark),
      themeMode: _currentThemeId == AppConstants.themeVelvetDark ? ThemeMode.dark : ThemeMode.light,
      home: _isReady
          ? const HomeLibraryScreen()
          : OnboardingScreen(onFinished: onOnboardingCompleted),
    );
  }
}
