import '../constants/app_constants.dart';

class TextSanitizer {
  /// Nettoie le texte extrait d'un PDF :
  /// - Supprime les retours à la ligne superflus et espaces multiples
  /// - Supprime les caractères non imprimables ou corrompus
  /// - Tronque intelligemment à une taille raisonnable pour l'IA
  static String sanitizeForAi(String rawText, {int maxChars = AppConstants.maxTextCharsForAi}) {
    if (rawText.isEmpty) return '';

    // 1. Remplacer les caractères de contrôle non imprimables (sauf retours à la ligne standards)
    String cleaned = rawText.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), ' ');

    // 2. Réduire les espaces horizontaux successifs
    cleaned = cleaned.replaceAll(RegExp(r'[ \t]+'), ' ');

    // 3. Réduire les sauts de lignes multiples (> 2 consécutifs)
    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    cleaned = cleaned.trim();

    // 4. Tronquer si la taille dépasse le plafond
    if (cleaned.length > maxChars) {
      cleaned = '${cleaned.substring(0, maxChars)}\n\n[...texte tronqué pour l\'analyse...]';
    }

    return cleaned;
  }
}
