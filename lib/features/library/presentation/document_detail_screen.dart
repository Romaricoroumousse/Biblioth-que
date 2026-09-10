import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../models/document_model.dart';
import '../../../services/ai_classification_service.dart';

class DocumentDetailScreen extends StatefulWidget {
  final DocumentModel document;
  final Function(String keyword)? onKeywordTap;

  const DocumentDetailScreen({
    super.key,
    required this.document,
    this.onKeywordTap,
  });

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> {
  late DocumentModel _doc;
  bool _isReanalyzing = false;

  @override
  void initState() {
    super.initState();
    _doc = widget.document;
    _markOpened();
  }

  Future<void> _markOpened() async {
    if (_doc.id != null) {
      await DatabaseHelper.instance.recordDocumentOpened(_doc.id!);
    }
  }

  Future<void> _openFile() async {
    final file = File(_doc.filePath);
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Le fichier est introuvable à cet emplacement. Il a peut-être été déplacé ou supprimé.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final result = await OpenFilex.open(_doc.filePath);
    if (result.type != ResultType.done && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Impossible d\'ouvrir le PDF : ${result.message}'),
        ),
      );
    }
  }

  Future<void> _toggleFavorite() async {
    final updated = _doc.copyWith(isFavorite: !_doc.isFavorite);
    if (updated.id != null) {
      await DatabaseHelper.instance.toggleFavorite(updated.id!, updated.isFavorite);
    }
    setState(() {
      _doc = updated;
    });
  }

  Future<void> _toggleExclude() async {
    final updated = _doc.copyWith(isExcluded: !_doc.isExcluded);
    if (updated.id != null) {
      await DatabaseHelper.instance.toggleExclude(updated.id!, updated.isExcluded);
    }
    setState(() {
      _doc = updated;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(updated.isExcluded
            ? 'Document exclu de l\'analyse IA.'
            : 'Document réintégré dans la bibliothèque.'),
      ),
    );
  }

  Future<void> _reanalyzeWithAi() async {
    setState(() {
      _isReanalyzing = true;
    });

    try {
      final file = File(_doc.filePath);
      final newDoc = await AiClassificationService.instance.processSingleFile(
        file: file,
        fileHash: _doc.fileHash,
        forceReanalysis: true,
      );

      if (!mounted) return;

      setState(() {
        _doc = newDoc;
        _isReanalyzing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Document réanalysé avec succès par Groq !'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isReanalyzing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur lors de la réanalyse : $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _editClassificationDialog() async {
    final domainCtrl = TextEditingController(text: _doc.domainName ?? '');
    final subCtrl = TextEditingController(text: _doc.subdomainName ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Modifier le classement'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: domainCtrl,
              decoration: const InputDecoration(labelText: 'Domaine principal'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: subCtrl,
              decoration: const InputDecoration(labelText: 'Sous-domaine'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );

    if (result == true && domainCtrl.text.trim().isNotEmpty) {
      final db = DatabaseHelper.instance;
      final newDomainId = await db.getOrCreateDomain(domainCtrl.text.trim(), isCustom: true);
      final newSubId = await db.getOrCreateSubdomain(newDomainId, subCtrl.text.trim().isEmpty ? 'Général' : subCtrl.text.trim());

      final updated = _doc.copyWith(
        domainId: newDomainId,
        subdomainId: newSubId,
        domainName: domainCtrl.text.trim(),
        subdomainName: subCtrl.text.trim(),
      );

      await db.updateDocument(updated);

      setState(() {
        _doc = updated;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final domainColor = AppConstants.domainColors[_doc.domainName] ?? Colors.indigo;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fiche Document'),
        actions: [
          IconButton(
            icon: Icon(
              _doc.isFavorite ? Icons.star : Icons.star_border,
              color: _doc.isFavorite ? Colors.amber : null,
            ),
            onPressed: _toggleFavorite,
            tooltip: 'Favori',
          ),
          PopupMenuButton<String>(
            onSelected: (val) {
              if (val == 'reanalyze') _reanalyzeWithAi();
              if (val == 'edit') _editClassificationDialog();
              if (val == 'exclude') _toggleExclude();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'reanalyze',
                child: Row(
                  children: [
                    Icon(Icons.refresh, size: 18),
                    SizedBox(width: 8),
                    Text('Réanalyser par l\'IA'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('Modifier le classement'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'exclude',
                child: Row(
                  children: [
                    Icon(
                      _doc.isExcluded ? Icons.check_circle_outline : Icons.block,
                      size: 18,
                      color: _doc.isExcluded ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Text(_doc.isExcluded ? 'Réintégrer l\'IA' : 'Exclure de l\'IA'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isReanalyzing
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Réanalyse avec le modèle Groq en cours...'),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // En-tête : Nom du fichier & Métadonnées
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: domainColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: domainColor.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.picture_as_pdf, color: domainColor, size: 32),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _doc.fileName,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _buildMetaRow(Icons.folder_outlined, _doc.filePath),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(child: _buildMetaRow(Icons.data_usage, _doc.formattedFileSize)),
                            Expanded(child: _buildMetaRow(Icons.pages, '${_doc.pageCount} pages')),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _buildMetaRow(Icons.calendar_today_outlined, _doc.formattedModifiedDate),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Badges de Taxonomie
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_doc.domainName != null)
                        Chip(
                          avatar: const Icon(Icons.category, size: 16),
                          label: Text(_doc.domainName!),
                          backgroundColor: domainColor.withOpacity(0.12),
                          side: BorderSide.none,
                        ),
                      if (_doc.subdomainName != null)
                        Chip(
                          avatar: const Icon(Icons.subdirectory_arrow_right, size: 16),
                          label: Text(_doc.subdomainName!),
                          side: BorderSide.none,
                        ),
                      if (_doc.level != null)
                        Chip(
                          avatar: const Icon(Icons.school, size: 16),
                          label: Text('Niveau : ${_doc.level!}'),
                          side: BorderSide.none,
                        ),
                      if (_doc.language != null)
                        Chip(
                          avatar: const Icon(Icons.language, size: 16),
                          label: Text(_doc.language!.toUpperCase()),
                          side: BorderSide.none,
                        ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Résumé intelligent IA
                  const Text(
                    'Résumé du document',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _doc.summary != null && _doc.summary!.isNotEmpty
                            ? _doc.summary!
                            : 'Aucun résumé disponible. Vous pouvez lancer une analyse IA.',
                        style: const TextStyle(fontSize: 14, height: 1.5, color: Colors.black87),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Mots-clés extraits
                  if (_doc.keywords.isNotEmpty) ...[
                    const Text(
                      'Mots-clés associés',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: _doc.keywords.map((kw) {
                        return ActionChip(
                          label: Text('# $kw'),
                          onPressed: () {
                            if (widget.onKeywordTap != null) {
                              widget.onKeywordTap!(kw);
                              Navigator.pop(context);
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Bouton d'action principal : Ouvrir le PDF
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _openFile,
                      icon: const Icon(Icons.launch),
                      label: const Text('Ouvrir le fichier original'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildMetaRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 15, color: Colors.grey.shade600),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
