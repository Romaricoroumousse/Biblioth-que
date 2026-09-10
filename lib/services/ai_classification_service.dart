import 'dart:io';
import '../core/constants/app_constants.dart';
import '../core/database/database_helper.dart';
import '../core/network/groq_api_client.dart';
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

  /// Analyse et classe un fichier PDF unique
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
      // Mettre à jour le chemin au cas où le fichier a été déplacé
      if (existingDoc.filePath != file.path) {
        final updated = existingDoc.copyWith(filePath: file.path);
        await db.updateDocument(updated);
        return updated;
      }
      return existingDoc;
    }

    // 2. Vérifier si le document a été exclu explicitement par l'utilisateur
    if (existingDoc != null && existingDoc.isExcluded) {
      return existingDoc;
    }

    // 3. Récupérer la clé Groq et la config
    final apiKey = await storage.getGroqApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Clé API Groq non configurée');
    }
    final model = await storage.getSelectedGroqModel();
    final pageLimit = await storage.getScanPageCount();

    // 4. Extraction du texte des premières pages
    final extraction = await PdfExtractorService.instance.extractText(file, pageLimit: pageLimit);
    final stat = await file.stat();
    final fileName = file.uri.pathSegments.last;

    // 5. Appel au modèle Groq
    AiAnalysisResult aiResult;
    try {
      aiResult = await GroqApiClient.instance.analyzeDocument(
        apiKey: apiKey,
        fileName: fileName,
        extractedText: extraction.text,
        model: model,
      );
    } catch (e) {
      // En cas d'erreur de quota ou réseau, on stocke en 'failed' ou 'pending'
      final failedDoc = DocumentModel(
        id: existingDoc?.id,
        filePath: file.path,
        fileName: fileName,
        fileHash: fileHash,
        fileSize: stat.size,
        pageCount: extraction.pageCount,
        modifiedDate: stat.modified.millisecondsSinceEpoch,
        summary: 'Échec de l\'analyse IA : $e',
        aiStatus: 'failed',
        createdAt: existingDoc?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
      );
      final id = await db.insertDocument(failedDoc);
      return failedDoc.copyWith(id: id);
    }

    // 6. Associer ou créer le Domaine et Sous-Domaine
    final domainId = await db.getOrCreateDomain(aiResult.domain, isCustom: true);
    final subdomainId = await db.getOrCreateSubdomain(domainId, aiResult.subdomain);

    // 7. Enregistrer le document
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
      domainName: aiResult.domain,
      subdomainName: aiResult.subdomain,
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

    for (int i = 0; i < total; i++) {
      final item = toProcess[i];
      onProgress(i + 1, total, item.fileName, 'Analyse intelligente avec Groq...');

      try {
        await processSingleFile(
          file: item.file,
          fileHash: item.fileHash,
          forceReanalysis: !skipAlreadyIndexed,
        );
      } catch (e) {
        // Continuer sur le document suivant sans interrompre la file d'attente
      }

      // Légère temporisation pour respecter les quotas de requêtes par minute (RPM)
      await Future.delayed(const Duration(milliseconds: 250));
    }
  }
}
