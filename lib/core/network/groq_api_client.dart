import '../constants/app_constants.dart';
import 'unified_ai_client.dart';
export 'unified_ai_client.dart';

class GroqApiClient {
  static final GroqApiClient instance = GroqApiClient._init();
  GroqApiClient._init();

  /// Teste la validité d'une clé API Groq
  Future<bool> testApiKey(String apiKey) async {
    final result = await UnifiedAiClient.instance.testApiKey(
      provider: AppConstants.providerGroq,
      apiKey: apiKey,
    );
    return result.isValid;
  }

  /// Analyse le contenu textuel et le nom d'un document PDF pour le classifier
  Future<AiAnalysisResult> analyzeDocument({
    required String apiKey,
    required String fileName,
    required String extractedText,
    String model = AppConstants.groqDefaultModel,
  }) async {
    return await UnifiedAiClient.instance.analyzeDocument(
      provider: AppConstants.providerGroq,
      apiKey: apiKey,
      fileName: fileName,
      extractedText: extractedText,
      model: model,
    );
  }
}
