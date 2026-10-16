import 'package:flutter/material.dart';
import 'core/constants/app_constants.dart';
import 'core/storage/secure_storage_service.dart';
import 'core/theme/app_theme.dart';
import 'features/library/presentation/home_library_screen.dart';
import 'features/onboarding/presentation/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SecureStorageService.instance.init();

  // L'application s'ouvre même sans clé API !
  final bool onboardingDone = await SecureStorageService.instance.isOnboardingCompleted();
  final String savedTheme = await SecureStorageService.instance.getSelectedTheme();

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
