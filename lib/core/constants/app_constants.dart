import 'package:flutter/material.dart';

class AppConstants {
  static const String appName = 'Bibliothèque PDF';
  static const String appVersion = '1.0.0';

  // Modèles Groq disponibles
  static const String groqDefaultModel = 'llama-3.3-70b-versatile';
  static const String groqFastModel = 'llama-3.1-8b-instant';
  static const String groqApiUrl = 'https://api.groq.com/openai/v1/chat/completions';

  // Paramètres par défaut d'extraction
  static const int defaultScanPageCount = 3;
  static const int minScanPageCount = 1;
  static const int maxScanPageCount = 10;
  static const int maxTextCharsForAi = 8000; // Limite raisonnable de tokens pour le résumé

  // Clés de stockage sécurisé et préférences
  static const String keyGroqApiKey = 'groq_api_key';
  static const String keySelectedModel = 'selected_groq_model';
  static const String keyScanPageCount = 'scan_page_count';
  static const String keyPrivacyAccepted = 'privacy_accepted';
  static const String keyOnboardingCompleted = 'onboarding_completed';
  static const String keyCustomFolders = 'custom_scan_folders';

  // Dossiers Android par défaut à inspecter
  static const List<String> defaultAndroidScanPaths = [
    '/storage/emulated/0/Download',
    '/storage/emulated/0/Documents',
    '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Documents',
    '/storage/emulated/0/WhatsApp/Media/WhatsApp Documents',
    '/storage/emulated/0/Telegram/Telegram Documents',
  ];

  // Niveaux académiques/professionnels possibles
  static const List<String> academicLevels = [
    'débutant',
    'intermédiaire',
    'avancé',
    'recherche',
  ];

  // Couleurs associées aux domaines
  static const Map<String, Color> domainColors = {
    'Informatique': Color(0xFF1E88E5),
    'Intelligence Artificielle': Color(0xFF7B1FA2),
    'Mathématiques': Color(0xFF00897B),
    'Statistiques': Color(0xFF00ACC1),
    'Économie': Color(0xFF43A047),
    'Finance': Color(0xFF2E7D32),
    'Droit': Color(0xFFD81B60),
    'Médecine': Color(0xFFE53935),
    'Physique': Color(0xFFFB8C00),
    'Chimie': Color(0xFF8E24AA),
    'Sciences Sociales': Color(0xFF6D4C41),
    'Gestion': Color(0xFF3949AB),
    'Comptabilité': Color(0xFF546E7A),
    'Agriculture': Color(0xFF7CB342),
    'Éducation': Color(0xFFF4511E),
    'Langues': Color(0xFF039BE5),
    'Littérature': Color(0xFF8D6E63),
    'Autre': Color(0xFF757575),
  };
}
