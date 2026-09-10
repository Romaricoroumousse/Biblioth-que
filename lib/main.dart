import 'package:flutter/material.dart';
import 'core/constants/app_constants.dart';
import 'core/storage/secure_storage_service.dart';
import 'core/theme/app_theme.dart';
import 'features/library/presentation/home_library_screen.dart';
import 'features/onboarding/presentation/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SecureStorageService.instance.init();

  final bool onboardingDone = await SecureStorageService.instance.isOnboardingCompleted();
  final bool hasKey = await SecureStorageService.instance.hasGroqApiKey();
  final bool isReady = onboardingDone && hasKey;

  runApp(SmartPdfLibraryApp(initialReady: isReady));
}

class SmartPdfLibraryApp extends StatefulWidget {
  final bool initialReady;

  const SmartPdfLibraryApp({super.key, required this.initialReady});

  @override
  State<SmartPdfLibraryApp> createState() => _SmartPdfLibraryAppState();
}

class _SmartPdfLibraryAppState extends State<SmartPdfLibraryApp> {
  late bool _isReady;

  @override
  void initState() {
    super.initState();
    _isReady = widget.initialReady;
  }

  void _onOnboardingCompleted() {
    setState(() {
      _isReady = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: _isReady
          ? const HomeLibraryScreen()
          : OnboardingScreen(onFinished: _onOnboardingCompleted),
    );
  }
}
