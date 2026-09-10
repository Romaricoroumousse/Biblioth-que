import 'dart:io';
import 'package:flutter/material.dart';
import '../../../models/domain_model.dart';
import '../../../services/ai_classification_service.dart';
import '../../../services/pdf_scanner_service.dart';

class ScanProgressDialog extends StatefulWidget {
  final VoidCallback onFinished;

  const ScanProgressDialog({super.key, required this.onFinished});

  @override
  State<ScanProgressDialog> createState() => _ScanProgressDialogState();
}

class _ScanProgressDialogState extends State<ScanProgressDialog> {
  String _status = 'Recherche des fichiers PDF sur votre appareil...';
  int _current = 0;
  int _total = 0;
  String _currentFileName = '';
  bool _isFinished = false;
  bool _isCancelled = false;
  int _newAnalyzedCount = 0;
  int _alreadyIndexedCount = 0;

  @override
  void initState() {
    super.initState();
    _startScanProcess();
  }

  Future<void> _startScanProcess() async {
    try {
      // 1. Découverte des fichiers
      final List<File> files = await PdfScannerService.instance.discoverPdfFiles();

      if (_isCancelled) return;

      if (files.isEmpty) {
        setState(() {
          _status = 'Aucun fichier PDF trouvé dans les dossiers explorés.';
          _isFinished = true;
        });
        return;
      }

      setState(() {
        _status = 'Vérification des empreintes et métadonnées (${files.length} PDF trouvés)...';
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

      setState(() {
        _current = 0;
        _total = toAnalyze.length;
        _status = 'Analyse intelligente avec Groq IA (${toAnalyze.length} nouveaux documents)...';
      });

      // 3. Analyse avec le LLM Groq
      for (int i = 0; i < toAnalyze.length; i++) {
        if (_isCancelled) break;

        final item = toAnalyze[i];
        setState(() {
          _current = i + 1;
          _currentFileName = item.fileName;
          _status = 'Classification Groq (${i + 1}/${toAnalyze.length})';
        });

        try {
          await AiClassificationService.instance.processSingleFile(
            file: item.file,
            fileHash: item.fileHash,
          );
          _newAnalyzedCount++;
        } catch (_) {}

        // Pause pour respecter les quotas de débit de Groq
        await Future.delayed(const Duration(milliseconds: 200));
      }

      if (mounted) {
        setState(() {
          _isFinished = true;
          _status = 'Scan terminé !';
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

  @override
  Widget build(BuildContext context) {
    final double progress = _total > 0 ? (_current / _total) : 0.0;

    return PopScope(
      canPop: _isFinished,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              _isFinished ? Icons.check_circle : Icons.sync,
              color: _isFinished ? Colors.green : Theme.of(context).primaryColor,
            ),
            const SizedBox(width: 10),
            Text(
              _isFinished ? 'Scan terminé' : 'Scan de la bibliothèque',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _status,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
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
            if (_isFinished) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '• $_newAnalyzedCount nouveau(x) document(s) classé(s) par l\'IA',
                      style: TextStyle(fontSize: 13, color: Colors.green.shade900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '• $_alreadyIndexedCount document(s) déjà répertorié(s)',
                      style: TextStyle(fontSize: 13, color: Colors.green.shade900),
                    ),
                  ],
                ),
              ),
            ],
          ],
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
