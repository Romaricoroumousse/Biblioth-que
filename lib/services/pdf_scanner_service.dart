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

  /// Récupère la liste de tous les dossiers à explorer (chemins standards, cartes SD et dossiers utilisateur)
  Future<List<String>> getSearchDirectories() async {
    final List<String> paths = [];

    void addDirIfValid(String p) {
      if (!paths.contains(p)) {
        try {
          final d = Directory(p);
          if (d.existsSync()) {
            paths.add(p);
          }
        } catch (_) {}
      }
    }

    // 1. Dossiers prioritaires à fort taux de PDF sur Android
    for (var defaultPath in AppConstants.defaultAndroidScanPaths) {
      addDirIfValid(defaultPath);
    }

    // Variantes de noms courantes sur différentes marques (Samsung, Xiaomi, OnePlus, etc.)
    final extraCommonPaths = [
      '/storage/emulated/0/Download',
      '/storage/emulated/0/Downloads',
      '/storage/emulated/0/Documents',
      '/storage/emulated/0/Document',
      '/storage/emulated/0/Books',
      '/storage/emulated/0/Book',
      '/storage/emulated/0/PDF',
      '/storage/emulated/0/Pdfs',
      '/storage/emulated/0/DCIM',
      '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Documents',
      '/storage/emulated/0/WhatsApp/Media/WhatsApp Documents',
      '/storage/emulated/0/Telegram/Telegram Documents',
      '/storage/emulated/0/Android/media/org.telegram.messenger/Telegram/Telegram Documents',
      '/sdcard/Download',
      '/sdcard/Downloads',
      '/sdcard/Documents',
      '/sdcard/Books',
    ];
    for (var p in extraCommonPaths) {
      addDirIfValid(p);
    }

    // 2. Dossiers configurés manuellement par l'utilisateur
    final customFolders = await SecureStorageService.instance.getCustomScanFolders();
    for (var customPath in customFolders) {
      addDirIfValid(customPath);
    }

    // 3. Racines principales globales (explorées en dernier si besoin)
    addDirIfValid('/storage/emulated/0');
    addDirIfValid('/sdcard');

    return paths;
  }

  /// Recherche robuste de tous les fichiers .pdf via parcours par file d'attente (BFS)
  /// Ignore les répertoires système restreints (Android/data, obb) sans interrompre le scan
  Future<List<File>> discoverPdfFiles({
    List<String>? targetDirectories,
    List<File>? directFiles,
  }) async {
    if (directFiles != null && directFiles.isNotEmpty) {
      return directFiles.where((f) => f.existsSync()).toList();
    }

    final directories = targetDirectories ?? await getSearchDirectories();
    final List<File> pdfFiles = [];
    final Set<String> visitedFilePaths = {};
    final Set<String> visitedDirPaths = {};

    for (var rootPath in directories) {
      final rootDir = Directory(rootPath);
      try {
        if (!rootDir.existsSync()) continue;
      } catch (_) {
        continue;
      }

      final List<Directory> queue = [rootDir];

      while (queue.isNotEmpty) {
        final currentDir = queue.removeAt(0);
        if (!visitedDirPaths.add(currentDir.path)) continue;

        try {
          final Stream<FileSystemEntity> stream = currentDir.list(followLinks: false);
          await for (final entity in stream.handleError((_) {})) {
            if (entity is File) {
              final pathLower = entity.path.toLowerCase();
              if (pathLower.endsWith('.pdf')) {
                if (visitedFilePaths.add(entity.path)) {
                  pdfFiles.add(entity);
                }
              }
            } else if (entity is Directory) {
              final dirName = entity.uri.pathSegments.isNotEmpty
                  ? entity.uri.pathSegments[entity.uri.pathSegments.length - (entity.uri.pathSegments.last.isEmpty ? 2 : 1)]
                  : entity.path.split(Platform.pathSeparator).last;

              final lowerName = dirName.toLowerCase();
              // Ignorer les répertoires système Android inaccessibles et dossiers cachés
              if (lowerName == 'android' ||
                  lowerName == 'data' ||
                  lowerName == 'obb' ||
                  lowerName.startsWith('.') ||
                  lowerName == '.thumbnails' ||
                  lowerName == 'cache') {
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
