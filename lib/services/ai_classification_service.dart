import 'dart:io';
import '../core/constants/app_constants.dart';
import '../core/database/database_helper.dart';
import '../core/network/unified_ai_client.dart';
import '../core/storage/secure_storage_service.dart';
import '../models/document_model.dart';
import 'pdf_extractor_service.dart';
import 'pdf_scanner_service.dart';

enum AnalysisStatus {
  idle,
  scanning,
  extractingText,
  callingAi,
  saving,
  completed,
  error,
}

class AiClassificationService {
  static final AiClassificationService instance = AiClassificationService._init();
  AiClassificationService._init();

  /// Analyse et classe un fichier PDF unique (supporte l'analyse IA ou l'indexation locale hors-ligne)
  Future<DocumentModel> processSingleFile({
    required File file,
    required String fileHash,
    bool forceReanalysis = false,
  }) async {
    final db = DatabaseHelper.instance;
    final storage = SecureStorageService.instance;

    // 1. Vérifier si déjà présent en BDD
    final existingDoc = await db.getDocumentByHash(fileHash);
    if (existingDoc != null && existingDoc.aiStatus == 'analyzed' && !forceReanalysis) {
      if (existingDoc.filePath != file.path) {
        final updated = existingDoc.copyWith(filePath: file.path);
        await db.updateDocument(updated);
        return updated;
      }
      return existingDoc;
    }

    // 2. Vérifier si le document a été exclu explicitement
    if (existingDoc != null && existingDoc.isExcluded) {
      return existingDoc;
    }

    // 3. Récupérer le fournisseur actif et la clé
    final provider = await storage.getActiveProvider();
    final apiKey = await storage.getApiKey(provider: provider);
    final model = await storage.getSelectedModel(provider: provider);
    final customEndpoint = await storage.getCustomEndpoint();
    final pageLimit = await storage.getScanPageCount();

    // 4. Extraction du texte des premières pages
    final extraction = await PdfExtractorService.instance.extractText(file, pageLimit: pageLimit);
    final stat = await file.stat();
    final fileName = file.uri.pathSegments.last;

    // 5. Indexation locale si aucune clé n'est configurée (Mode sans IA / Hors-ligne)
    if (apiKey == null || apiKey.trim().isEmpty) {
      final String inferredDomain = _inferDomainFromFileName(fileName);
      final domainId = await db.getOrCreateDomain(inferredDomain, isCustom: false);
      final subdomainId = await db.getOrCreateSubdomain(domainId, 'Général');

      final localDoc = DocumentModel(
        id: existingDoc?.id,
        filePath: file.path,
        fileName: fileName,
        fileHash: fileHash,
        fileSize: stat.size,
        pageCount: extraction.pageCount,
        modifiedDate: stat.modified.millisecondsSinceEpoch,
        domainId: domainId,
        subdomainId: subdomainId,
        domainName: inferredDomain,
        subdomainName: 'Général',
        summary: 'Document PDF de ${extraction.pageCount} page(s) (${fileName}). En attente d\'analyse IA.',
        keywords: [fileName.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '').replaceAll('_', ' ')],
        language: 'français',
        level: 'intermédiaire',
        isFavorite: existingDoc?.isFavorite ?? false,
        isExcluded: false,
        aiStatus: 'pending',
        createdAt: existingDoc?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
      );

      final id = await db.insertDocument(localDoc);
      return localDoc.copyWith(id: id);
    }

    // 6. Appel au modèle d'IA sélectionné
    AiAnalysisResult aiResult;
    try {
      aiResult = await UnifiedAiClient.instance.analyzeDocument(
        provider: provider,
        apiKey: apiKey,
        fileName: fileName,
        extractedText: extraction.text,
        model: model,
        customEndpoint: customEndpoint,
      );
    } catch (e) {
      // En cas d'erreur de quota ou réseau, conserver en statut local avec le domaine inféré
      final String fallbackDomain = _inferDomainFromFileName(fileName);
      final domainId = await db.getOrCreateDomain(fallbackDomain, isCustom: false);
      final subdomainId = await db.getOrCreateSubdomain(domainId, 'Général');

      final failedDoc = DocumentModel(
        id: existingDoc?.id,
        filePath: file.path,
        fileName: fileName,
        fileHash: fileHash,
        fileSize: stat.size,
        pageCount: extraction.pageCount,
        modifiedDate: stat.modified.millisecondsSinceEpoch,
        domainId: domainId,
        subdomainId: subdomainId,
        domainName: fallbackDomain,
        subdomainName: 'Général',
        summary: 'Document classé dans $fallbackDomain. En attente d\'analyse IA dès régénération des tokens.',
        keywords: [fileName.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '').replaceAll('_', ' ')],
        language: 'français',
        level: 'intermédiaire',
        isFavorite: existingDoc?.isFavorite ?? false,
        isExcluded: false,
        aiStatus: 'pending',
        createdAt: existingDoc?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
      );
      final id = await db.insertDocument(failedDoc);

      if (e is AiQuotaExceededException) {
        rethrow;
      }
      return failedDoc.copyWith(id: id);
    }

    // 7. Enregistrer avec les résultats de l'IA
    String finalDomain = aiResult.domain.trim();
    if (finalDomain.isEmpty) {
      finalDomain = _inferDomainFromFileName(fileName);
    }
    String finalSubdomain = aiResult.subdomain.trim();
    if (finalSubdomain.isEmpty) {
      finalSubdomain = 'Général';
    }

    final domainId = await db.getOrCreateDomain(finalDomain, isCustom: true);
    final subdomainId = await db.getOrCreateSubdomain(domainId, finalSubdomain);

    final completeDoc = DocumentModel(
      id: existingDoc?.id,
      filePath: file.path,
      fileName: fileName,
      fileHash: fileHash,
      fileSize: stat.size,
      pageCount: extraction.pageCount,
      modifiedDate: stat.modified.millisecondsSinceEpoch,
      domainId: domainId,
      subdomainId: subdomainId,
      domainName: finalDomain,
      subdomainName: finalSubdomain,
      summary: aiResult.summary,
      keywords: aiResult.keywords,
      language: aiResult.language,
      level: aiResult.level,
      isFavorite: existingDoc?.isFavorite ?? false,
      isExcluded: false,
      aiStatus: 'analyzed',
      createdAt: existingDoc?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
    );

    final id = await db.insertDocument(completeDoc);
    return completeDoc.copyWith(id: id);
  }

  /// Déduction heuristique enrichie du domaine à partir du nom du fichier
  String _inferDomainFromFileName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.contains('math') || lower.contains('algebre') || lower.contains('analyse') || lower.contains('geometrie')) return 'Mathématiques';
    if (lower.contains('info') || lower.contains('prog') || lower.contains('python') || lower.contains('java') || lower.contains('web') || lower.contains('code') || lower.contains('algo')) return 'Informatique';
    if (lower.contains('ia') || lower.contains('ai') || lower.contains('data') || lower.contains('machine learning') || lower.contains('deep learning')) return 'Intelligence Artificielle';
    if (lower.contains('droit') || lower.contains('juridique') || lower.contains('loi') || lower.contains('code civil')) return 'Droit';
    if (lower.contains('eco') || lower.contains('finance') || lower.contains('compta') || lower.contains('gestion') || lower.contains('banque') || lower.contains('bourse')) return 'Économie & Finance';
    if (lower.contains('sante') || lower.contains('med') || lower.contains('bio') || lower.contains('anatomie') || lower.contains('pharma')) return 'Médecine & Santé';
    if (lower.contains('physique') || lower.contains('chimie') || lower.contains('science')) return 'Sciences';
    if (lower.contains('roman') || lower.contains('litterature') || lower.contains('poesie') || lower.contains('theatre') || lower.contains('livre')) return 'Littérature';
    if (lower.contains('histoire') || lower.contains('geo') || lower.contains('politique')) return 'Histoire & Géographie';
    if (lower.contains('anglais') || lower.contains('francais') || lower.contains('espagnol') || lower.contains('langue')) return 'Langues';
    if (lower.contains('cours') || lower.contains('tp') || lower.contains('td') || lower.contains('examen') || lower.contains('exercice')) return 'Documents & Cours';
    return 'Documents & Cours';
  }

  /// Traitement d'un lot de documents avec callback de progression en temps réel
  Future<void> processBatch({
    required List<ScannedPdfCandidate> candidates,
    required Function(int current, int total, String currentFileName, String statusText) onProgress,
    bool skipAlreadyIndexed = true,
  }) async {
    final toProcess = skipAlreadyIndexed 
        ? candidates.where((c) => !c.isAlreadyIndexed).toList()
        : candidates;

    final total = toProcess.length;
    final providerName = await SecureStorageService.instance.getActiveProviderName();
    final hasKey = await SecureStorageService.instance.hasApiKey();

    for (int i = 0; i < total; i++) {
      final item = toProcess[i];
      final status = hasKey 
          ? 'Analyse avec $providerName...' 
          : 'Indexation locale rapide...';
      onProgress(i + 1, total, item.fileName, status);

      try {
        await processSingleFile(
          file: item.file,
          fileHash: item.fileHash,
          forceReanalysis: !skipAlreadyIndexed,
        );
      } catch (_) {}

      // Petite pause pour fluidité de l'interface
      await Future.delayed(const Duration(milliseconds: 150));
    }
  }

  /// Classement et indexation immédiate en mode 100% hors-ligne (sans appel réseau)
  Future<DocumentModel> processSingleFileLocal({
    required File file,
    required String fileHash,
  }) async {
    final db = DatabaseHelper.instance;
    final stat = await file.stat();
    final fileName = file.uri.pathSegments.last;
    final extraction = await PdfExtractorService.instance.extractText(file, pageLimit: 1);

    final existingDoc = await db.getDocumentByHash(fileHash);
    if (existingDoc != null && existingDoc.aiStatus == 'analyzed') {
      return existingDoc;
    }

    final String inferredDomain = _inferDomainFromFileName(fileName);
    final domainId = await db.getOrCreateDomain(inferredDomain, isCustom: false);
    final subdomainId = await db.getOrCreateSubdomain(domainId, 'Général');

    final localDoc = DocumentModel(
      id: existingDoc?.id,
      filePath: file.path,
      fileName: fileName,
      fileHash: fileHash,
      fileSize: stat.size,
      pageCount: extraction.pageCount,
      modifiedDate: stat.modified.millisecondsSinceEpoch,
      domainId: domainId,
      subdomainId: subdomainId,
      domainName: inferredDomain,
      subdomainName: 'Général',
      summary: 'Document classé dans $inferredDomain. Prêt pour lecture hors-ligne.',
      keywords: [fileName.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '').replaceAll('_', ' ')],
      language: 'français',
      level: 'intermédiaire',
      isFavorite: existingDoc?.isFavorite ?? false,
      isExcluded: false,
      aiStatus: 'pending',
      createdAt: existingDoc?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
    );

    final id = await db.insertDocument(localDoc);
    return localDoc.copyWith(id: id);
  }
}
