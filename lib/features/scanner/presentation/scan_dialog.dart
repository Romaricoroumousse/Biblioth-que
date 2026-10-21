import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/network/unified_ai_client.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../services/ai_classification_service.dart';
import '../../../services/pdf_scanner_service.dart';
import 'ai_classification_dialog.dart';

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
  bool _isFinished = false;
  bool _isEmptyResult = false;
  bool _isCancelled = false;
  bool _hasKey = false;
  int _newIndexedCount = 0;
  int _alreadyIndexedCount = 0;
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    _startScanProcess();
  }

  void _openAiClassification() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AiClassificationDialog(
        onFinished: widget.onFinished,
      ),
    );
  }

  Future<void> _startScanProcess({List<File>? specificFiles}) async {
    final hasKey = await SecureStorageService.instance.hasApiKey();
    setState(() {
      _isFinished = false;
      _isEmptyResult = false;
      _current = 0;
      _total = 0;
      _newIndexedCount = 0;
      _alreadyIndexedCount = 0;
      _pendingCount = 0;
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
        _status = 'Vérification et répertoriation (${files.length} PDF trouvés)...';
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

      final toIndex = candidates.where((c) => !c.isAlreadyIndexed).toList();
      _alreadyIndexedCount = candidates.where((c) => c.isAlreadyIndexed).length;

      // 3. Répertoire rapide de tous les nouveaux PDF dans SQLite
      int newlyAdded = 0;
      if (toIndex.isNotEmpty) {
        setState(() {
          _current = 0;
          _total = toIndex.length;
          _status = 'Enregistrement dans la bibliothèque (${toIndex.length} documents)...';
        });

        for (int i = 0; i < toIndex.length; i++) {
          if (_isCancelled) break;
          final item = toIndex[i];
          setState(() {
            _current = i + 1;
            _currentFileName = item.fileName;
            _status = 'Répertoire du document (${i + 1}/${toIndex.length}) : ${item.fileName}';
          });

          try {
            final existing = await DatabaseHelper.instance.getDocumentByHash(item.fileHash);
            if (existing == null) {
              await AiClassificationService.instance.processSingleFileLocal(
                file: item.file,
                fileHash: item.fileHash,
              );
              newlyAdded++;
            }
          } catch (_) {}
        }
      }

      final pending = await DatabaseHelper.instance.countPendingDocuments();

      if (mounted) {
        setState(() {
          _newIndexedCount = newlyAdded;
          _pendingCount = pending;
          _isFinished = true;
          if (_newIndexedCount > 0) {
            _status = '🎉 Scan terminé ! $_newIndexedCount nouveau(x) document(s) répertorié(s).';
          } else if (_pendingCount > 0) {
            _status = 'Tous vos PDF sont répertoriés ($_pendingCount prêt(s) pour le classement).';
          } else {
            _status = 'Tous vos documents sont répertoriés et classés à jour !';
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
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green, size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _newIndexedCount > 0
                                  ? '$_newIndexedCount nouveau(x) document(s) répertorié(s)'
                                  : 'Documents à jour dans la bibliothèque',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green.shade900),
                            ),
                          ),
                        ],
                      ),
                      if (_alreadyIndexedCount > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          '• $_alreadyIndexedCount document(s) déjà présent(s)',
                          style: TextStyle(fontSize: 12, color: Colors.green.shade800),
                        ),
                      ],
                      const Divider(height: 16),
                      Text(
                        _newIndexedCount > 0 || _pendingCount > 0
                            ? 'Vos documents sont répertoriés. Cliquez sur "Classer par IA" pour créer vos domaines thématiques et sous-domaines automatiquement !'
                            : 'Tous vos documents sont déjà répertoriés et classés.',
                        style: TextStyle(fontSize: 12, color: Colors.green.shade900, height: 1.3),
                      ),
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
          if (_isFinished) ...[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onFinished();
              },
              child: const Text('Voir la bibliothèque'),
            ),
            if (_newIndexedCount > 0 || _pendingCount > 0)
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onFinished();
                  _openAiClassification();
                },
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: Text(
                  _newIndexedCount > 0
                      ? 'Classer par IA ($_newIndexedCount)'
                      : 'Classer par IA ($_pendingCount)',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              )
            else
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onFinished();
                },
                child: const Text('Fermer'),
              ),
          ],
        ],
      ),
    );
  }
}
