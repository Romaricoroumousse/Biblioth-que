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

    // Racine principale de stockage Android si accessible
    const rootPath = '/storage/emulated/0';
    if (await Directory(rootPath).exists()) {
      paths.add(rootPath);
    }

    // Dossiers spécifiques par défaut
    for (var defaultPath in AppConstants.defaultAndroidScanPaths) {
      if (!paths.contains(defaultPath) && await Directory(defaultPath).exists()) {
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

  /// Recherche robuste de tous les fichiers .pdf via parcours par file d'attente (BFS)
  /// Ignore les répertoires système restreints (Android/data, obb) sans interrompre le scan
  Future<List<File>> discoverPdfFiles({List<String>? targetDirectories}) async {
    final directories = targetDirectories ?? await getSearchDirectories();
    final List<File> pdfFiles = [];
    final Set<String> visitedFilePaths = {};
    final Set<String> visitedDirPaths = {};

    for (var rootPath in directories) {
      final rootDir = Directory(rootPath);
      if (!await rootDir.exists()) continue;

      final List<Directory> queue = [rootDir];

      while (queue.isNotEmpty) {
        final currentDir = queue.removeAt(0);
        if (!visitedDirPaths.add(currentDir.path)) continue;

        try {
          final List<FileSystemEntity> entities = await currentDir.list(followLinks: false).toList();

          for (final entity in entities) {
            if (entity is File) {
              final pathLower = entity.path.toLowerCase();
              if (pathLower.endsWith('.pdf')) {
                if (visitedFilePaths.add(entity.path)) {
                  pdfFiles.add(entity);
                }
              }
            } else if (entity is Directory) {
              final dirName = entity.uri.pathSegments.length >= 2
                  ? entity.uri.pathSegments[entity.uri.pathSegments.length - 2]
                  : entity.path.split(Platform.pathSeparator).last;

              // Ignorer les répertoires système Android inaccessibles et dossiers cachés
              final lowerName = dirName.toLowerCase();
              if (lowerName == 'android' ||
                  lowerName == 'data' ||
                  lowerName == 'obb' ||
                  lowerName.startsWith('.') ||
                  lowerName == '.thumbnails') {
                continue;
              }

              queue.add(entity);
            }
          }
        } catch (_) {
          // Ignorer silencieusement ce sous-dossier restreint et continuer la file
        }
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

        // Vérifier si le document existe déjà avec ce hash et est complètement analysé
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
