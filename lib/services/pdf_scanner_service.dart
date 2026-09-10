import 'dart:io';
import '../core/constants/app_constants.dart';
import '../core/database/database_helper.dart';
import '../core/storage/secure_storage_service.dart';
import '../core/utils/file_hash.dart';

class ScannedPdfCandidate {
  final File file;
  final String path;
  final String fileName;
  final int fileSize;
  final int modifiedDate;
  final String fileHash;
  final bool isAlreadyIndexed;

  ScannedPdfCandidate({
    required this.file,
    required this.path,
    required this.fileName,
    required this.fileSize,
    required this.modifiedDate,
    required this.fileHash,
    required this.isAlreadyIndexed,
  });
}

class PdfScannerService {
  static final PdfScannerService instance = PdfScannerService._init();
  PdfScannerService._init();

  /// Récupère la liste de tous les dossiers à explorer
  Future<List<String>> getSearchDirectories() async {
    final List<String> paths = [];

    // Dossiers par défaut
    for (var defaultPath in AppConstants.defaultAndroidScanPaths) {
      if (await Directory(defaultPath).exists()) {
        paths.add(defaultPath);
      }
    }

    // Dossiers configurés par l'utilisateur
    final customFolders = await SecureStorageService.instance.getCustomScanFolders();
    for (var customPath in customFolders) {
      if (!paths.contains(customPath) && await Directory(customPath).exists()) {
        paths.add(customPath);
      }
    }

    return paths;
  }

  /// Recherche récursive de tous les fichiers .pdf
  Future<List<File>> discoverPdfFiles({List<String>? targetDirectories}) async {
    final directories = targetDirectories ?? await getSearchDirectories();
    final List<File> pdfFiles = [];
    final Set<String> visitedPaths = {};

    for (var dirPath in directories) {
      try {
        final dir = Directory(dirPath);
        if (!await dir.exists()) continue;

        await for (var entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File && entity.path.toLowerCase().endsWith('.pdf')) {
            if (!visitedPaths.contains(entity.path)) {
              visitedPaths.add(entity.path);
              pdfFiles.add(entity);
            }
          }
        }
      } catch (_) {
        // Ignorer les dossiers sans droit d'accès
      }
    }

    return pdfFiles;
  }

  /// Inspecte un lot de fichiers PDF et identifie ceux qui nécessitent une analyse IA
  Future<List<ScannedPdfCandidate>> inspectFiles(
    List<File> files, {
    Function(int current, int total)? onProgress,
  }) async {
    final List<ScannedPdfCandidate> candidates = [];
    final db = DatabaseHelper.instance;

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      try {
        final stat = await file.stat();
        final fileName = file.uri.pathSegments.last;
        final hash = await FileHash.calculate(file);

        // Vérifier si le document existe déjà avec ce hash
        final existingDoc = await db.getDocumentByHash(hash);
        final isIndexed = existingDoc != null && existingDoc.aiStatus == 'analyzed';

        candidates.add(ScannedPdfCandidate(
          file: file,
          path: file.path,
          fileName: fileName,
          fileSize: stat.size,
          modifiedDate: stat.modified.millisecondsSinceEpoch,
          fileHash: hash,
          isAlreadyIndexed: isIndexed,
        ));
      } catch (_) {}

      if (onProgress != null) {
        onProgress(i + 1, files.length);
      }
    }

    return candidates;
  }
}
