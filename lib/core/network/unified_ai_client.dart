import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/app_constants.dart';

class AiAnalysisResult {
  final String domain;
  final String subdomain;
  final String summary;
  final List<String> keywords;
  final String language;
  final String level;

  AiAnalysisResult({
    required this.domain,
    required this.subdomain,
    required this.summary,
    required this.keywords,
    required this.language,
    required this.level,
  });

  factory AiAnalysisResult.fromJson(Map<String, dynamic> json) {
    List<String> kw = [];
    if (json['mots_cles'] is List) {
      kw = (json['mots_cles'] as List).map((e) => e.toString()).toList();
    } else if (json['keywords'] is List) {
      kw = (json['keywords'] as List).map((e) => e.toString()).toList();
    }

    return AiAnalysisResult(
      domain: (json['domaine'] ?? json['domain'] ?? 'Documents & Cours').toString().trim(),
      subdomain: (json['sous_domaine'] ?? json['subdomain'] ?? 'Général').toString().trim(),
      summary: (json['resume'] ?? json['summary'] ?? 'Aucun résumé disponible.').toString().trim(),
      keywords: kw,
      language: (json['langue'] ?? json['language'] ?? 'français').toString().trim(),
      level: (json['niveau'] ?? json['level'] ?? 'intermédiaire').toString().trim(),
    );
  }
}

class AiTestResult {
  final bool isValid;
  final String message;
  final int? statusCode;

  AiTestResult({
    required this.isValid,
    required this.message,
    this.statusCode,
  });
}

class UnifiedAiClient {
  static final UnifiedAiClient instance = UnifiedAiClient._init();
  UnifiedAiClient._init();

  /// Détecte automatiquement le fournisseur à partir de la syntaxe de la clé
  static String detectProviderFromKey(String key) {
    final k = key.trim();
    if (k.startsWith('gsk_')) return AppConstants.providerGroq;
    if (k.startsWith('xai-')) return AppConstants.providerXai;
    if (k.startsWith('AIza')) return AppConstants.providerGemini;
    if (k.startsWith('sk-or-')) return AppConstants.providerOpenRouter;
    if (k.startsWith('sk-')) return AppConstants.providerOpenAi;
    return AppConstants.providerGroq;
  }

  /// Récupère l'URL de l'endpoint selon le fournisseur
  String getEndpointForProvider(String provider, {String? customEndpoint}) {
    if (provider == AppConstants.providerCustom && customEndpoint != null && customEndpoint.isNotEmpty) {
      return customEndpoint.trim();
    }
    final info = AppConstants.supportedProviders.firstWhere(
      (p) => p.id == provider,
      orElse: () => AppConstants.supportedProviders.first,
    );
    return info.defaultEndpoint;
  }

  /// Récupère le modèle par défaut pour un fournisseur
  String getDefaultModelForProvider(String provider) {
    final info = AppConstants.supportedProviders.firstWhere(
      (p) => p.id == provider,
      orElse: () => AppConstants.supportedProviders.first,
    );
    return info.defaultModel;
  }

  /// Teste la validité d'une clé API avec un diagnostic précis
  Future<AiTestResult> testApiKey({
    required String provider,
    required String apiKey,
    String? model,
    String? customEndpoint,
  }) async {
    final trimmedKey = apiKey.trim();
    final endpoint = getEndpointForProvider(provider, customEndpoint: customEndpoint);
    final chosenModel = (model != null && model.isNotEmpty) ? model : getDefaultModelForProvider(provider);

    try {
      final headers = <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
        'User-Agent': 'SmartPdfLibrary/1.0',
        'Accept': 'application/json',
      };

      if (trimmedKey.isNotEmpty) {
        headers['Authorization'] = 'Bearer $trimmedKey';
      }

      final payload = {
        'model': chosenModel,
        'messages': [
          {'role': 'user', 'content': 'Reponds simplement: OK'}
        ],
        'max_tokens': 10,
      };

      final response = await http
          .post(
            Uri.parse(endpoint),
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return AiTestResult(
          isValid: true,
          message: 'Connexion réussie ! Modèle $chosenModel opérationnel.',
          statusCode: 200,
        );
      }

      // Si le modèle est obsolète/introuvable (404), tenter automatiquement le modèle recommandé
      if (response.statusCode == 404) {
        if (provider == AppConstants.providerGroq && chosenModel != 'meta-llama/llama-4-scout-17b-16e-instruct') {
          final fallbackRes = await testApiKey(
            provider: provider,
            apiKey: apiKey,
            model: 'meta-llama/llama-4-scout-17b-16e-instruct',
            customEndpoint: customEndpoint,
          );
          if (fallbackRes.isValid) {
            return AiTestResult(
              isValid: true,
              message: 'Connexion réussie avec le modèle à jour : meta-llama/llama-4-scout-17b-16e-instruct',
              statusCode: 200,
            );
          }
        } else if (provider == AppConstants.providerGemini && chosenModel != 'gemini-2.0-flash') {
          final fallbackRes = await testApiKey(
            provider: provider,
            apiKey: apiKey,
            model: 'gemini-2.0-flash',
            customEndpoint: customEndpoint,
          );
          if (fallbackRes.isValid) {
            return AiTestResult(
              isValid: true,
              message: 'Connexion réussie avec le modèle à jour : gemini-2.0-flash',
              statusCode: 200,
            );
          }
        }
      }

      String errorDetail = '';
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map && decoded['error'] != null) {
          final err = decoded['error'];
          errorDetail = err is Map ? (err['message'] ?? '') : err.toString();
        }
      } catch (_) {}

      if (response.statusCode == 401) {
        return AiTestResult(
          isValid: false,
          message: 'Clé API invalide ou non reconnue (Erreur 401). Vérifiez la saisie.',
          statusCode: 401,
        );
      } else if (response.statusCode == 403) {
        return AiTestResult(
          isValid: false,
          message: 'Accès refusé (Erreur 403) : clé restreinte ou pays non éligible.',
          statusCode: 403,
        );
      } else if (response.statusCode == 404) {
        return AiTestResult(
          isValid: false,
          message: 'Modèle "$chosenModel" introuvable (Erreur 404). Utilisez meta-llama/llama-4-scout-17b-16e-instruct ou vérifiez le nom.',
          statusCode: 404,
        );
      } else if (response.statusCode == 429) {
        return AiTestResult(
          isValid: false,
          message: 'Quota d\'appels dépassé (Erreur 429). Réessayez dans un moment.',
          statusCode: 429,
        );
      }

      final msg = errorDetail.isNotEmpty 
          ? 'Erreur (${response.statusCode}) : $errorDetail' 
          : 'Erreur HTTP (${response.statusCode}) reçue du fournisseur.';

      return AiTestResult(
        isValid: false,
        message: msg,
        statusCode: response.statusCode,
      );
    } catch (e) {
      return AiTestResult(
        isValid: false,
        message: 'Erreur de connexion : $e',
      );
    }
  }

  /// Analyse et classe un document PDF avec n'importe quel fournisseur d'IA
  Future<AiAnalysisResult> analyzeDocument({
    required String provider,
    required String apiKey,
    required String fileName,
    required String extractedText,
    String? model,
    String? customEndpoint,
  }) async {
    final endpoint = getEndpointForProvider(provider, customEndpoint: customEndpoint);
    final chosenModel = (model != null && model.isNotEmpty) ? model : getDefaultModelForProvider(provider);

    const String systemPrompt = '''
Tu es un documentaliste universitaire et scientifique expert.
Ton rôle est d'analyser le nom de fichier et les extraits des premières pages d'un document PDF pour le cataloguer avec précision.

Tu DOIS répondre STRICTEMENT sous forme d'un objet JSON valide respectant cette structure exacte :
{
  "domaine": "Domaine principal (ex: Informatique, Intelligence Artificielle, Mathématiques, Économie, Finance, Droit, Médecine, Sciences Sociales, Physique, Chimie, Gestion, Agriculture, Éducation, Documents & Cours, etc.)",
  "sous_domaine": "Sous-domaine précis (ex: Machine Learning, Microéconomie, Droit des affaires, Statistique descriptive...)",
  "resume": "Résumé clair et synthétique en 2 ou 3 phrases du sujet traité",
  "mots_cles": ["mot1", "mot2", "mot3", "mot4", "mot5"],
  "langue": "français | anglais | espagnol | autre",
  "niveau": "débutant | intermédiaire | avancé | recherche"
}

Règles impératives :
1. Si le texte fourni est court ou incomplet, déduis le domaine et le sujet le plus probable à partir du nom du fichier et du contexte disponible.
2. Si le document ne rentre dans aucune catégorie usuelle, choisis "Documents & Cours" ou "Autre".
3. Ne fournis AUCUN texte explicatif en dehors de l'objet JSON.
''';

    final String userPrompt = '''
Nom du fichier : "$fileName"

Extrait des premières pages du document :
"""
$extractedText
"""
''';

    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      'User-Agent': 'SmartPdfLibrary/1.0',
      'Accept': 'application/json',
    };

    if (apiKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${apiKey.trim()}';
    }

    final payload = {
      'model': chosenModel,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
      'temperature': 0.1,
      'max_tokens': 1000,
    };

    if (provider == AppConstants.providerGroq || provider == AppConstants.providerOpenAi) {
      payload['response_format'] = {'type': 'json_object'};
    }

    final response = await http
        .post(
          Uri.parse(endpoint),
          headers: headers,
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 35));

    if (response.statusCode == 200) {
      final decodedBody = jsonDecode(utf8.decode(response.bodyBytes));
      final content = decodedBody['choices'][0]['message']['content'];
      final jsonResult = _extractJson(content.toString());
      return AiAnalysisResult.fromJson(jsonResult);
    } else if (response.statusCode == 404 && provider == AppConstants.providerGroq && chosenModel != 'meta-llama/llama-4-scout-17b-16e-instruct') {
      // Re-tentative automatique avec le nouveau modèle Groq
      return await analyzeDocument(
        provider: provider,
        apiKey: apiKey,
        fileName: fileName,
        extractedText: extractedText,
        model: 'meta-llama/llama-4-scout-17b-16e-instruct',
        customEndpoint: customEndpoint,
      );
    } else if (response.statusCode == 404 && provider == AppConstants.providerGemini && chosenModel != 'gemini-2.0-flash') {
      // Re-tentative automatique avec le nouveau modèle Gemini
      return await analyzeDocument(
        provider: provider,
        apiKey: apiKey,
        fileName: fileName,
        extractedText: extractedText,
        model: 'gemini-2.0-flash',
        customEndpoint: customEndpoint,
      );
    } else {
      final errorBody = utf8.decode(response.bodyBytes);
      throw Exception('Erreur API ($provider - ${response.statusCode}) : $errorBody');
    }
  }

  /// Extraction robuste du JSON même si le modèle inclut des blocs markdown
  Map<String, dynamic> _extractJson(String raw) {
    String cleaned = raw.trim();

    if (cleaned.startsWith('```json')) {
      cleaned = cleaned.substring(7);
    } else if (cleaned.startsWith('```')) {
      cleaned = cleaned.substring(3);
    }

    if (cleaned.endsWith('```')) {
      cleaned = cleaned.substring(0, cleaned.length - 3);
    }
    cleaned = cleaned.trim();

    try {
      return jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (_) {}

    final match = RegExp(r'\{[\s\S]*\}').firstMatch(cleaned);
    if (match != null) {
      return jsonDecode(match.group(0)!) as Map<String, dynamic>;
    }

    throw FormatException('Impossible de parser la réponse JSON de l\'IA: $raw');
  }
}
