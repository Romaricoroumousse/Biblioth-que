import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/network/unified_ai_client.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../services/ai_classification_service.dart';
import '../../../services/pdf_scanner_service.dart';

class ScanProgressDialog extends StatefulWidget {
  final VoidCallback onFinished;
  final List<File>? initialFiles;

  const ScanProgressDialog({
    super.key,
    required this.onFinished,
    this.initialFiles,
  });

  @override
  State<ScanProgressDialog> createState() => _ScanProgressDialogState();
}

class _ScanProgressDialogState extends State<ScanProgressDialog> {
  String _status = 'Recherche des fichiers PDF sur votre appareil...';
  int _current = 0;
  int _total = 0;
  String _currentFileName = '';
  String _lastClassifiedInfo = '';
  bool _isFinished = false;
  bool _isEmptyResult = false;
  bool _isCancelled = false;
  bool _hasKey = false;
  int _newAnalyzedCount = 0;
  int _alreadyIndexedCount = 0;
  int _localCount = 0;
  final Map<String, int> _domainCounts = {};

  @override
  void initState() {
    super.initState();
    _startScanProcess();
  }

  Future<void> _startScanProcess({List<File>? specificFiles}) async {
    final hasKey = await SecureStorageService.instance.hasApiKey();
    setState(() {
      _isFinished = false;
      _isEmptyResult = false;
      _current = 0;
      _total = 0;
      _newAnalyzedCount = 0;
      _localCount = 0;
      _domainCounts.clear();
      _lastClassifiedInfo = '';
      _hasKey = hasKey;
      _status = 'Recherche des fichiers PDF sur votre appareil...';
    });

    try {
      // 1. Découverte des fichiers ou utilisation des fichiers fournis
      final List<File> files = specificFiles ??
          widget.initialFiles ??
          await PdfScannerService.instance.discoverPdfFiles();

      if (_isCancelled) return;

      if (files.isEmpty) {
        setState(() {
          _status = 'Aucun fichier PDF trouvé automatiquement.';
          _isEmptyResult = true;
          _isFinished = true;
        });
        return;
      }

      setState(() {
        _status = 'Vérification des empreintes (${files.length} PDF trouvés)...';
      });

      // 2. Inspection des doublons et des documents déjà analysés
      final candidates = await PdfScannerService.instance.inspectFiles(
        files,
        onProgress: (cur, tot) {
          if (mounted) {
            setState(() {
              _current = cur;
              _total = tot;
            });
          }
        },
      );

      if (_isCancelled) return;

      final toAnalyze = candidates.where((c) => !c.isAlreadyIndexed).toList();
      _alreadyIndexedCount = candidates.where((c) => c.isAlreadyIndexed).length;

      if (toAnalyze.isEmpty) {
        setState(() {
          _status = 'Tous les documents PDF sont déjà répertoriés et à jour !';
          _isFinished = true;
        });
        return;
      }

      final providerName = await SecureStorageService.instance.getActiveProviderName();

      setState(() {
        _current = 0;
        _total = toAnalyze.length;
        _status = hasKey
            ? 'Classification avec $providerName (${toAnalyze.length} documents)...'
            : 'Indexation locale (${toAnalyze.length} documents)...';
      });

      bool quotaExceeded = false;

      // 3. Analyse avec l'IA ou indexation locale
      for (int i = 0; i < toAnalyze.length; i++) {
        if (_isCancelled) break;

        final item = toAnalyze[i];
        setState(() {
          _current = i + 1;
          _currentFileName = item.fileName;
          _status = quotaExceeded
              ? 'Tokens épuisés (recharge en 1 min) : Classement local (${i + 1}/${toAnalyze.length})'
              : (hasKey
                  ? 'Classification avec $providerName (${i + 1}/${toAnalyze.length})'
                  : 'Classement local sans IA (${i + 1}/${toAnalyze.length})');
        });

        dynamic processedDoc;
        try {
          if (quotaExceeded || !hasKey) {
            processedDoc = await AiClassificationService.instance.processSingleFileLocal(
              file: item.file,
              fileHash: item.fileHash,
            );
            _localCount++;
          } else {
            processedDoc = await AiClassificationService.instance.processSingleFile(
              file: item.file,
              fileHash: item.fileHash,
            );
            _newAnalyzedCount++;
          }
        } on AiQuotaExceededException {
          quotaExceeded = true;
          processedDoc = await AiClassificationService.instance.processSingleFileLocal(
            file: item.file,
            fileHash: item.fileHash,
          );
          _localCount++;
        } catch (_) {
          try {
            processedDoc = await AiClassificationService.instance.processSingleFileLocal(
              file: item.file,
              fileHash: item.fileHash,
            );
            _localCount++;
          } catch (_) {}
        }

        if (mounted && processedDoc != null) {
          setState(() {
            final dom = processedDoc.domainName as String;
            final sub = processedDoc.subdomainName as String;
            _domainCounts[dom] = (_domainCounts[dom] ?? 0) + 1;
            _lastClassifiedInfo = '➔ $dom ($sub)';
          });
        }

        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (mounted) {
        setState(() {
          _isFinished = true;
          if (quotaExceeded) {
            _status = 'Scan terminé ! Limite de débit atteinte : vos documents restants ont été rangés localement et seront analysés automatiquement dès régénération.';
          } else {
            _status = 'Scan et classement terminés avec succès !';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Erreur lors du scan : $e';
          _isFinished = true;
        });
      }
    }
  }

  Future<void> _pickAndScanFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: true,
    );
    if (result != null && result.paths.isNotEmpty) {
      final selected = result.paths
          .whereType<String>()
          .map((p) => File(p))
          .where((f) => f.existsSync())
          .toList();
      if (selected.isNotEmpty) {
        _startScanProcess(specificFiles: selected);
      }
    }
  }

  Future<void> _pickAndScanFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir != null) {
      await SecureStorageService.instance.addCustomScanFolder(dir);
      final discovered = await PdfScannerService.instance.discoverPdfFiles(targetDirectories: [dir]);
      if (discovered.isNotEmpty) {
        _startScanProcess(specificFiles: discovered);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucun PDF trouvé dans ce dossier sélectionné.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final double progress = _total > 0 ? (_current / _total) : 0.0;

    return PopScope(
      canPop: _isFinished,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const AppLogo(size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _isFinished ? 'Scan terminé' : 'Scan de la bibliothèque',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_hasKey && !_isFinished) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome_outlined, color: Colors.blue.shade800, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Mode sans clé API : classement par thèmes locaux. Pour une analyse IA complète de chaque page, renseignez votre clé Groq ou Gemini dans Paramètres.',
                          style: TextStyle(fontSize: 11, color: Colors.blue.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              Text(
                _status,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 16),
              if (!_isFinished && _total > 0) ...[
                LinearProgressIndicator(
                  value: progress > 1.0 ? 1.0 : progress,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$_current / $_total',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    Text(
                      '${(progress * 100).toInt()}%',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                if (_currentFileName.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    _currentFileName,
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey.shade700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (_lastClassifiedInfo.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _lastClassifiedInfo,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ] else if (!_isFinished) ...[
                const Center(child: CircularProgressIndicator()),
              ],

              // Si 0 document trouvé automatiquement
              if (_isEmptyResult) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.amber.shade900, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Autorisation ou emplacement des fichiers',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.amber.shade900),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Android protège les dossiers de votre appareil. Vous pouvez choisir vos PDF directement ou autoriser l\'application :',
                        style: TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: _pickAndScanFiles,
                  icon: const Icon(Icons.file_upload_outlined, size: 18),
                  label: const Text('Sélectionner des PDF manuellement'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _pickAndScanFolder,
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  label: const Text('Choisir un dossier (ex: Téléchargements)'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(40),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                if (Platform.isAndroid) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => openAppSettings(),
                    icon: const Icon(Icons.settings_outlined, size: 18),
                    label: const Text('Activer "Accès aux fichiers" dans Paramètres'),
                  ),
                ],
              ],

              // Résultat après scan réussi
              if (_isFinished && !_isEmptyResult) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_newAnalyzedCount > 0)
                        Text(
                          '• $_newAnalyzedCount document(s) classé(s) par l\'IA',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green.shade900),
                        ),
                      if (_localCount > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          '• $_localCount document(s) classé(s) par thématique locale',
                          style: TextStyle(fontSize: 12, color: Colors.green.shade800),
                        ),
                      ],
                      if (_alreadyIndexedCount > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          '• $_alreadyIndexedCount document(s) déjà présent(s)',
                          style: TextStyle(fontSize: 12, color: Colors.green.shade800),
                        ),
                      ],
                      if (_domainCounts.isNotEmpty) ...[
                        const Divider(height: 16),
                        Text(
                          'Domaines créés / alimentés :',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade900),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _domainCounts.entries.map((entry) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.green.shade300),
                              ),
                              child: Text(
                                '${entry.key} (${entry.value})',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green.shade900,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (!_isFinished)
            TextButton(
              onPressed: () {
                _isCancelled = true;
                Navigator.of(context).pop();
                widget.onFinished();
              },
              child: const Text('Arrêter'),
            ),
          if (_isFinished)
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onFinished();
              },
              child: const Text('Fermer'),
            ),
        ],
      ),
    );
  }
}
