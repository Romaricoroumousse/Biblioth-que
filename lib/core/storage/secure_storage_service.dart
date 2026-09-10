import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';

class SecureStorageService {
  static final SecureStorageService instance = SecureStorageService._init();
  late final FlutterSecureStorage _secureStorage;
  SharedPreferences? _prefs;

  SecureStorageService._init() {
    _secureStorage = const FlutterSecureStorage(
      aOptions: AndroidOptions(
        encryptedSharedPreferences: true,
      ),
    );
  }

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // ==================== CLÉ API GROQ (SÉCURISÉE) ====================

  Future<void> setGroqApiKey(String apiKey) async {
    await _secureStorage.write(key: AppConstants.keyGroqApiKey, value: apiKey.trim());
  }

  Future<String?> getGroqApiKey() async {
    return await _secureStorage.read(key: AppConstants.keyGroqApiKey);
  }

  Future<void> deleteGroqApiKey() async {
    await _secureStorage.delete(key: AppConstants.keyGroqApiKey);
  }

  Future<bool> hasGroqApiKey() async {
    final key = await getGroqApiKey();
    return key != null && key.isNotEmpty;
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

  Future<String> getSelectedGroqModel() async {
    await init();
    return _prefs?.getString(AppConstants.keySelectedModel) ?? AppConstants.groqDefaultModel;
  }

  Future<void> setSelectedGroqModel(String model) async {
    await init();
    await _prefs?.setString(AppConstants.keySelectedModel, model);
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
}
