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
      domain: (json['domaine'] ?? json['domain'] ?? 'Autre').toString().trim(),
      subdomain: (json['sous_domaine'] ?? json['subdomain'] ?? 'Général').toString().trim(),
      summary: (json['resume'] ?? json['summary'] ?? 'Aucun résumé disponible.').toString().trim(),
      keywords: kw,
      language: (json['langue'] ?? json['language'] ?? 'français').toString().trim(),
      level: (json['niveau'] ?? json['level'] ?? 'intermédiaire').toString().trim(),
    );
  }
}

class GroqApiClient {
  static final GroqApiClient instance = GroqApiClient._init();
  GroqApiClient._init();

  /// Teste la validité d'une clé API Groq avec une requête ultra-légère
  Future<bool> testApiKey(String apiKey) async {
    try {
      final response = await http.post(
        Uri.parse(AppConstants.groqApiUrl),
        headers: {
          'Authorization': 'Bearer ${apiKey.trim()}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': AppConstants.groqFastModel,
          'messages': [
            {'role': 'user', 'content': 'ping'}
          ],
          'max_tokens': 5,
        }),
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Analyse le contenu textuel et le nom d'un document PDF pour le classifier
  Future<AiAnalysisResult> analyzeDocument({
    required String apiKey,
    required String fileName,
    required String extractedText,
    String model = AppConstants.groqDefaultModel,
  }) async {
    const String systemPrompt = '''
Tu es un documentaliste universitaire et scientifique expert.
Ton rôle est d'analyser le nom de fichier et les extraits des premières pages d'un document PDF pour le cataloguer avec précision.

Tu DOIS répondre STRICTEMENT sous forme d'un objet JSON valide respectant cette structure exacte :
{
  "domaine": "Domaine principal (ex: Informatique, Mathématiques, Économie, Finance, Droit, Médecine, Sciences Sociales, Physique, Chimie, Gestion, Agriculture, Éducation, Littérature, etc.)",
  "sous_domaine": "Sous-domaine précis (ex: Machine Learning, Microéconomie, Droit des affaires, Statistique descriptive...)",
  "resume": "Résumé clair et synthétique en 2 ou 3 phrases du sujet traité",
  "mots_cles": ["mot1", "mot2", "mot3", "mot4", "mot5"],
  "langue": "français | anglais | espagnol | autre",
  "niveau": "débutant | intermédiaire | avancé | recherche"
}

Règles impératives :
1. Si le texte fourni est court ou incomplet, déduis le domaine et le sujet le plus probable à partir du nom du fichier et du contexte disponible.
2. Si le document ne rentre dans aucune catégorie usuelle, crée un domaine clair et pertinent.
3. Ne fournis AUCUN texte explicatif en dehors de l'objet JSON.
''';

    final String userPrompt = '''
Nom du fichier : "$fileName"

Extrait des premières pages du document :
"""
$extractedText
"""
''';

    try {
      final response = await http.post(
        Uri.parse(AppConstants.groqApiUrl),
        headers: {
          'Authorization': 'Bearer ${apiKey.trim()}',
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': userPrompt},
          ],
          'temperature': 0.1,
          'response_format': {'type': 'json_object'},
          'max_tokens': 1000,
        }),
      ).timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final decodedBody = jsonDecode(utf8.decode(response.bodyBytes));
        final content = decodedBody['choices'][0]['message']['content'];
        final jsonResult = jsonDecode(content);
        return AiAnalysisResult.fromJson(jsonResult);
      } else {
        final errorBody = response.body;
        throw Exception('Erreur API Groq (${response.statusCode}) : $errorBody');
      }
    } catch (e) {
      rethrow;
    }
  }
}
