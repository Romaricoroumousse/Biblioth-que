import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';

/// Service de persistance ultra-robuste et résistant aux pannes.
/// Utilise SharedPreferences (sandbox privé de l'application) comme moteur principal
/// pour éliminer tout risque de crash Keystore Android ou d'écran noir au démarrage.
class SecureStorageService {
  static final SecureStorageService instance = SecureStorageService._init();
  SharedPreferences? _prefs;

  SecureStorageService._init();

  Future<void> init() async {
    if (_prefs != null) return;
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('Avertissement SharedPreferences init: $e');
    }
  }

  // ==================== GESTION UNIVERSELLE DES CLÉS IA ====================

  /// Fournisseur IA actuellement sélectionné
  Future<String> getActiveProvider() async {
    await init();
    return _prefs?.getString(AppConstants.keyActiveProvider) ?? AppConstants.providerGroq;
  }

  Future<void> setActiveProvider(String provider) async {
    await init();
    try {
      await _prefs?.setString(AppConstants.keyActiveProvider, provider);
    } catch (_) {}
  }

  /// Nom convivial du fournisseur actif
  Future<String> getActiveProviderName() async {
    final activeId = await getActiveProvider();
    final info = AppConstants.supportedProviders.firstWhere(
      (p) => p.id == activeId,
      orElse: () => AppConstants.supportedProviders.first,
    );
    return info.name;
  }

  /// Récupère la clé API du fournisseur (ou du fournisseur actif si non spécifié)
  Future<String?> getApiKey({String? provider}) async {
    await init();
    final prov = provider ?? await getActiveProvider();
    final storageKey = '${AppConstants.keyAiApiKey}_$prov';

    // 1. SharedPreferences en priorité absolue (0 crash Keystore, instantané)
    try {
      final prefKey = _prefs?.getString(storageKey);
      if (prefKey != null && prefKey.trim().isNotEmpty) return prefKey.trim();

      // Rétrocompatibilité Groq
      if (prov == AppConstants.providerGroq) {
        final legacyPref = _prefs?.getString(AppConstants.keyGroqApiKey);
        if (legacyPref != null && legacyPref.trim().isNotEmpty) return legacyPref.trim();
      }

      final currentActive = _prefs?.getString('current_active_api_key');
      if (currentActive != null && currentActive.trim().isNotEmpty) return currentActive.trim();

      // Vérifier les clés alternatives dans SharedPreferences
      for (final p in AppConstants.supportedProviders) {
        final altKey = '${AppConstants.keyAiApiKey}_${p.id}';
        final altPref = _prefs?.getString(altKey);
        if (altPref != null && altPref.trim().isNotEmpty) {
          await setActiveProvider(p.id);
          return altPref.trim();
        }
      }
    } catch (e) {
      debugPrint('Erreur lecture clé SharedPreferences: $e');
    }

    // 2. Migration legacy de FlutterSecureStorage (protégée avec timeout court)
    try {
      const sec = FlutterSecureStorage();
      final key = await sec.read(key: storageKey).timeout(const Duration(milliseconds: 300));
      if (key != null && key.trim().isNotEmpty) {
        await _prefs?.setString(storageKey, key.trim());
        return key.trim();
      }
    } catch (_) {}

    return null;
  }

  /// Enregistre la clé API pour un fournisseur donné de façon synchrone et permanente
  Future<void> setApiKey(String apiKey, {String? provider}) async {
    await init();
    final prov = provider ?? await getActiveProvider();
    final storageKey = '${AppConstants.keyAiApiKey}_$prov';
    final cleaned = apiKey.trim();

    try {
      if (cleaned.isNotEmpty) {
        await _prefs?.setString(storageKey, cleaned);
        await _prefs?.setString('current_active_api_key', cleaned);

        if (prov == AppConstants.providerGroq || cleaned.startsWith('gsk_')) {
          await _prefs?.setString(AppConstants.keyGroqApiKey, cleaned);
          await _prefs?.setString('${AppConstants.keyAiApiKey}_groq', cleaned);
        }
      } else {
        await _prefs?.remove(storageKey);
        await _prefs?.remove('current_active_api_key');
        if (prov == AppConstants.providerGroq) {
          await _prefs?.remove(AppConstants.keyGroqApiKey);
          await _prefs?.remove('${AppConstants.keyAiApiKey}_groq');
        }
      }
    } catch (e) {
      debugPrint('Erreur écriture SharedPreferences: $e');
    }

    // Sauvegarde secondaire silencieuse dans FlutterSecureStorage (si supporté)
    try {
      const sec = FlutterSecureStorage();
      if (cleaned.isNotEmpty) {
        await sec.write(key: storageKey, value: cleaned).timeout(const Duration(milliseconds: 500));
      } else {
        await sec.delete(key: storageKey).timeout(const Duration(milliseconds: 500));
      }
    } catch (_) {}
  }

  /// Vérifie si une clé est enregistrée
  Future<bool> hasApiKey({String? provider}) async {
    final key = await getApiKey(provider: provider);
    return key != null && key.isNotEmpty;
  }

  /// Supprime la clé d'un fournisseur
  Future<void> deleteApiKey({String? provider}) async {
    await init();
    final prov = provider ?? await getActiveProvider();
    final storageKey = '${AppConstants.keyAiApiKey}_$prov';

    try {
      await _prefs?.remove(storageKey);
      await _prefs?.remove('current_active_api_key');
      if (prov == AppConstants.providerGroq) {
        await _prefs?.remove(AppConstants.keyGroqApiKey);
        await _prefs?.remove('${AppConstants.keyAiApiKey}_groq');
      }
    } catch (_) {}

    try {
      const sec = FlutterSecureStorage();
      await sec.delete(key: storageKey).timeout(const Duration(milliseconds: 300));
      if (prov == AppConstants.providerGroq) {
        await sec.delete(key: AppConstants.keyGroqApiKey).timeout(const Duration(milliseconds: 300));
      }
    } catch (_) {}
  }

  /// Modèle sélectionné pour un fournisseur
  Future<String> getSelectedModel({String? provider}) async {
    await init();
    final prov = provider ?? await getActiveProvider();
    final key = '${AppConstants.keySelectedModel}_$prov';
    final custom = _prefs?.getString(key);

    // Migration automatique des modèles obsolètes stockés précédemment
    if (custom != null && custom.isNotEmpty) {
      if (prov == AppConstants.providerGroq && custom == 'llama-3.3-70b-versatile') {
        const modernGroq = 'meta-llama/llama-4-scout-17b-16e-instruct';
        await _prefs?.setString(key, modernGroq);
        return modernGroq;
      }
      if (prov == AppConstants.providerGemini && (custom == 'gemini-1.0-pro' || custom == 'gemini-1.5-flash-latest')) {
        const modernGemini = 'gemini-2.0-flash';
        await _prefs?.setString(key, modernGemini);
        return modernGemini;
      }
      return custom;
    }

    final info = AppConstants.supportedProviders.firstWhere(
      (p) => p.id == prov,
      orElse: () => AppConstants.supportedProviders.first,
    );
    return info.defaultModel;
  }

  Future<void> setSelectedModel(String model, {String? provider}) async {
    await init();
    final prov = provider ?? await getActiveProvider();
    final key = '${AppConstants.keySelectedModel}_$prov';
    await _prefs?.setString(key, model);
  }

  /// Endpoint personnalisé (pour le mode "Autre IA")
  Future<String> getCustomEndpoint() async {
    await init();
    return _prefs?.getString(AppConstants.keyCustomEndpoint) ?? 'http://localhost:11434/v1/chat/completions';
  }

  Future<void> setCustomEndpoint(String url) async {
    await init();
    await _prefs?.setString(AppConstants.keyCustomEndpoint, url.trim());
  }

  // ==================== MÉTHODES GROQ (RÉTROCOMPATIBILITÉ) ====================

  Future<void> setGroqApiKey(String apiKey) async {
    await setApiKey(apiKey, provider: AppConstants.providerGroq);
  }

  Future<String?> getGroqApiKey() async {
    return await getApiKey(provider: AppConstants.providerGroq);
  }

  Future<void> deleteGroqApiKey() async {
    await deleteApiKey(provider: AppConstants.providerGroq);
  }

  Future<bool> hasGroqApiKey() async {
    return await hasApiKey(provider: AppConstants.providerGroq);
  }

  Future<String> getSelectedGroqModel() async {
    return await getSelectedModel(provider: AppConstants.providerGroq);
  }

  Future<void> setSelectedGroqModel(String model) async {
    await setSelectedModel(model, provider: AppConstants.providerGroq);
  }

  // ==================== PRÉFÉRENCES UTILISATEUR ====================

  Future<bool> isOnboardingCompleted() async {
    await init();
    return _prefs?.getBool(AppConstants.keyOnboardingCompleted) ?? false;
  }

  Future<void> setOnboardingCompleted(bool completed) async {
    await init();
    await _prefs?.setBool(AppConstants.keyOnboardingCompleted, completed);
  }

  Future<bool> isPrivacyAccepted() async {
    await init();
    return _prefs?.getBool(AppConstants.keyPrivacyAccepted) ?? false;
  }

  Future<void> setPrivacyAccepted(bool accepted) async {
    await init();
    await _prefs?.setBool(AppConstants.keyPrivacyAccepted, accepted);
  }

  Future<int> getScanPageCount() async {
    await init();
    return _prefs?.getInt(AppConstants.keyScanPageCount) ?? AppConstants.defaultScanPageCount;
  }

  Future<void> setScanPageCount(int count) async {
    await init();
    await _prefs?.setInt(AppConstants.keyScanPageCount, count.clamp(AppConstants.minScanPageCount, AppConstants.maxScanPageCount));
  }

  Future<List<String>> getCustomScanFolders() async {
    await init();
    return _prefs?.getStringList(AppConstants.keyCustomFolders) ?? [];
  }

  Future<void> addCustomScanFolder(String folderPath) async {
    await init();
    final current = await getCustomScanFolders();
    if (!current.contains(folderPath)) {
      current.add(folderPath);
      await _prefs?.setStringList(AppConstants.keyCustomFolders, current);
    }
  }

  Future<void> removeCustomScanFolder(String folderPath) async {
    await init();
    final current = await getCustomScanFolders();
    current.remove(folderPath);
    await _prefs?.setStringList(AppConstants.keyCustomFolders, current);
  }

  // ==================== THÈMES & EXPÉRIENCE HUMAINE ====================

  Future<String> getSelectedTheme() async {
    await init();
    return _prefs?.getString(AppConstants.keySelectedTheme) ?? AppConstants.themeClassicWarm;
  }

  Future<void> setSelectedTheme(String themeId) async {
    await init();
    await _prefs?.setString(AppConstants.keySelectedTheme, themeId);
  }

  Future<bool> isAutoScanEnabled() async {
    await init();
    return _prefs?.getBool(AppConstants.keyAutoScanNewDocs) ?? true;
  }

  Future<void> setAutoScanEnabled(bool enabled) async {
    await init();
    await _prefs?.setBool(AppConstants.keyAutoScanNewDocs, enabled);
  }
}
