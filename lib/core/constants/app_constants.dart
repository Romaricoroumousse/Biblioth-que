import 'package:flutter/material.dart';

class AiProviderInfo {
  final String id;
  final String name;
  final String defaultEndpoint;
  final String defaultModel;
  final List<String> availableModels;
  final String keyHint;
  final String keyHelpUrl;
  final String keyPrefix;
  final bool isCustom;

  const AiProviderInfo({
    required this.id,
    required this.name,
    required this.defaultEndpoint,
    required this.defaultModel,
    required this.availableModels,
    required this.keyHint,
    required this.keyHelpUrl,
    required this.keyPrefix,
    this.isCustom = false,
  });
}

class AppConstants {
  static const String appName = 'Bibliothèque PDF';
  static const String appVersion = '1.0.0';

  // Fournisseurs d'IA supportés
  static const String providerGroq = 'groq';
  static const String providerXai = 'xai';
  static const String providerGemini = 'gemini';
  static const String providerOpenAi = 'openai';
  static const String providerDeepSeek = 'deepseek';
  static const String providerMistral = 'mistral';
  static const String providerOpenRouter = 'openrouter';
  static const String providerCustom = 'custom';

  static const List<AiProviderInfo> supportedProviders = [
    AiProviderInfo(
      id: providerGroq,
      name: 'Groq (Gratuit & Ultra-rapide)',
      defaultEndpoint: 'https://api.groq.com/openai/v1/chat/completions',
      defaultModel: 'meta-llama/llama-4-scout-17b-16e-instruct',
      availableModels: [
        'meta-llama/llama-4-scout-17b-16e-instruct',
        'llama-3.1-8b-instant',
        'llama-3.3-70b-specdec',
        'qwen-qwq-32b',
        'mixtral-8x7b-32768',
      ],
      keyHint: 'gsk_...',
      keyHelpUrl: 'https://console.groq.com/keys',
      keyPrefix: 'gsk_',
    ),
    AiProviderInfo(
      id: providerXai,
      name: 'xAI (Grok)',
      defaultEndpoint: 'https://api.x.ai/v1/chat/completions',
      defaultModel: 'grok-2-latest',
      availableModels: [
        'grok-2-latest',
        'grok-2',
        'grok-beta',
        'grok-vision-beta',
      ],
      keyHint: 'xai-...',
      keyHelpUrl: 'https://console.x.ai',
      keyPrefix: 'xai-',
    ),
    AiProviderInfo(
      id: providerGemini,
      name: 'Google Gemini (Gratuit & Très précis)',
      defaultEndpoint: 'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
      defaultModel: 'gemini-2.0-flash',
      availableModels: [
        'gemini-2.0-flash',
        'gemini-1.5-flash',
        'gemini-1.5-pro',
        'gemini-2.0-flash-lite-preview-02-05',
      ],
      keyHint: 'AIzaSy...',
      keyHelpUrl: 'https://aistudio.google.com/app/apikey',
      keyPrefix: 'AIza',
    ),
    AiProviderInfo(
      id: providerOpenAi,
      name: 'OpenAI (ChatGPT)',
      defaultEndpoint: 'https://api.openai.com/v1/chat/completions',
      defaultModel: 'gpt-4o-mini',
      availableModels: [
        'gpt-4o-mini',
        'gpt-4o',
        'o3-mini',
        'gpt-4-turbo',
      ],
      keyHint: 'sk-proj-... ou sk-...',
      keyHelpUrl: 'https://platform.openai.com/api-keys',
      keyPrefix: 'sk-',
    ),
    AiProviderInfo(
      id: providerDeepSeek,
      name: 'DeepSeek',
      defaultEndpoint: 'https://api.deepseek.com/chat/completions',
      defaultModel: 'deepseek-chat',
      availableModels: [
        'deepseek-chat',
        'deepseek-reasoner',
      ],
      keyHint: 'sk-...',
      keyHelpUrl: 'https://platform.deepseek.com',
      keyPrefix: 'sk-',
    ),
    AiProviderInfo(
      id: providerMistral,
      name: 'Mistral AI',
      defaultEndpoint: 'https://api.mistral.ai/v1/chat/completions',
      defaultModel: 'mistral-small-latest',
      availableModels: [
        'mistral-small-latest',
        'mistral-large-latest',
        'open-mistral-nemo',
        'codestral-latest',
      ],
      keyHint: 'Collez votre clé Mistral...',
      keyHelpUrl: 'https://console.mistral.ai/api-keys',
      keyPrefix: '',
    ),
    AiProviderInfo(
      id: providerOpenRouter,
      name: 'OpenRouter (Toutes les IA réunies)',
      defaultEndpoint: 'https://openrouter.ai/api/v1/chat/completions',
      defaultModel: 'google/gemini-2.0-flash-exp:free',
      availableModels: [
        'google/gemini-2.0-flash-exp:free',
        'meta-llama/llama-3.3-70b-instruct:free',
        'deepseek/deepseek-r1:free',
        'openai/gpt-4o-mini',
      ],
      keyHint: 'sk-or-v1-...',
      keyHelpUrl: 'https://openrouter.ai/keys',
      keyPrefix: 'sk-or-',
    ),
    AiProviderInfo(
      id: providerCustom,
      name: 'Autre IA / Personnalisée (OpenAI compatible, Ollama...)',
      defaultEndpoint: 'http://localhost:11434/v1/chat/completions',
      defaultModel: 'llama3',
      availableModels: ['llama3', 'mistral', 'qwen2.5', 'deepseek-r1'],
      keyHint: 'Clé API (optionnelle pour Ollama local)',
      keyHelpUrl: '',
      keyPrefix: '',
      isCustom: true,
    ),
  ];

  // Rétrocompatibilité Groq
  static const String groqDefaultModel = 'meta-llama/llama-4-scout-17b-16e-instruct';
  static const String groqFastModel = 'llama-3.1-8b-instant';
  static const String groqApiUrl = 'https://api.groq.com/openai/v1/chat/completions';

  // Paramètres par défaut d'extraction
  static const int defaultScanPageCount = 3;
  static const int minScanPageCount = 1;
  static const int maxScanPageCount = 10;
  static const int maxTextCharsForAi = 8000;

  // Clés de stockage
  static const String keyActiveProvider = 'active_ai_provider';
  static const String keyAiApiKey = 'ai_api_key';
  static const String keyCustomEndpoint = 'custom_ai_endpoint';
  static const String keyCustomModel = 'custom_ai_model';
  static const String keyGroqApiKey = 'groq_api_key'; // Préservé pour migration
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
    'Documents & Cours': Color(0xFF0D9488),
    'Autre': Color(0xFF757575),
  };
}
