import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/network/unified_ai_client.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../models/document_model.dart';
import '../../../services/ai_classification_service.dart';

class AiClassificationDialog extends StatefulWidget {
  final VoidCallback onFinished;
  final List<DocumentModel>? targetDocuments;

  const AiClassificationDialog({
    super.key,
    required this.onFinished,
    this.targetDocuments,
  });

  @override
  State<AiClassificationDialog> createState() => _AiClassificationDialogState();
}

class _AiClassificationDialogState extends State<AiClassificationDialog> {
  final TextEditingController _apiKeyController = TextEditingController();

  List<DocumentModel> _docsToClassify = [];
  int _currentIndex = 0;
  String _currentFileName = '';
  String _lastClassifiedBadge = '';
  String _statusMessage = 'Préparation des documents...';
  bool _isLoading = true;
  bool _isClassifying = false;
  bool _isFinished = false;
  bool _isCancelled = false;
  bool _needsApiKey = false;
  int _quotaWaitSeconds = 0;
  Timer? _countdownTimer;

  final Map<String, int> _domainSummary = {};
  final List<Map<String, String>> _recentClassified = [];
  String _activeProviderName = 'Groq';
  String _activeModel = '';

  @override
  void initState() {
    super.initState();
    _initAndCheckKey();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _initAndCheckKey() async {
    final storage = SecureStorageService.instance;
    final provider = await storage.getActiveProvider();
    final providerName = await storage.getActiveProviderName();
    final model = await storage.getSelectedModel(provider: provider);
    final key = await storage.getApiKey(provider: provider);

    setState(() {
      _activeProviderName = providerName;
      _activeModel = model;
    });

    if (key == null || key.trim().isEmpty) {
      setState(() {
        _isLoading = false;
        _needsApiKey = true;
        _statusMessage = 'Une clé API ($providerName) est nécessaire pour classer les documents.';
      });
      return;
    }

    await _loadPendingDocuments();
  }

  Future<void> _loadPendingDocuments() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Chargement des documents à classer...';
    });

    List<DocumentModel> docs = [];
    if (widget.targetDocuments != null && widget.targetDocuments!.isNotEmpty) {
      docs = widget.targetDocuments!;
    } else {
      docs = await DatabaseHelper.instance.getAllPendingDocuments();
      if (docs.isEmpty) {
        // Si aucun pending, proposer de reclasser les récents
        docs = await DatabaseHelper.instance.getRecentDocuments(limit: 30);
      }
    }

    if (!mounted) return;

    if (docs.isEmpty) {
      setState(() {
        _isLoading = false;
        _isFinished = true;
        _statusMessage = 'Aucun document PDF en attente de classement dans votre bibliothèque.';
      });
      return;
    }

    setState(() {
      _docsToClassify = docs;
      _isLoading = false;
    });

    _startClassification();
  }

  Future<void> _saveKeyAndStart() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) return;

    final storage = SecureStorageService.instance;
    final prov = UnifiedAiClient.detectProviderFromKey(key);
    await storage.setActiveProvider(prov);
    await storage.setApiKey(key, provider: prov);

    final providerName = await storage.getActiveProviderName();
    final model = await storage.getSelectedModel(provider: prov);

    setState(() {
      _needsApiKey = false;
      _activeProviderName = providerName;
      _activeModel = model;
    });

    await _loadPendingDocuments();
  }

  Future<void> _startClassification() async {
    if (_docsToClassify.isEmpty || _isCancelled) return;

    setState(() {
      _isClassifying = true;
      _isFinished = false;
      _currentIndex = 0;
      _domainSummary.clear();
      _recentClassified.clear();
    });

    for (int i = 0; i < _docsToClassify.length; i++) {
      if (_isCancelled) break;

      final doc = _docsToClassify[i];
      final file = File(doc.filePath);

      setState(() {
        _currentIndex = i + 1;
        _currentFileName = doc.fileName;
        _statusMessage = 'Analyse de ${_activeProviderName} (${i + 1}/${_docsToClassify.length})...';
      });

      if (!file.existsSync()) {
        continue;
      }

      DocumentModel? resultDoc;
      try {
        resultDoc = await AiClassificationService.instance.processSingleFile(
          file: file,
          fileHash: doc.fileHash,
          forceReanalysis: true,
        );
      } on AiQuotaExceededException catch (e) {
        // Gestion gracieuse du quota : compte à rebours puis réessai
        final waitSec = e.retryAfterSeconds ?? 20;
        await _handleQuotaCooldown(waitSec);

        if (_isCancelled) break;

        // Réessayer une fois après la pause
        try {
          resultDoc = await AiClassificationService.instance.processSingleFile(
            file: file,
            fileHash: doc.fileHash,
            forceReanalysis: true,
          );
        } catch (_) {
          resultDoc = await AiClassificationService.instance.processSingleFileLocal(
            file: file,
            fileHash: doc.fileHash,
          );
        }
      } catch (err) {
        // En cas d'autre erreur (modèle / réseau), fallback local
        debugPrint('Erreur classification sur ${doc.fileName}: $err');
        resultDoc = await AiClassificationService.instance.processSingleFileLocal(
          file: file,
          fileHash: doc.fileHash,
        );
      }

      if (mounted && resultDoc != null) {
        final dom = resultDoc.domainName ?? 'Documents & Cours';
        final sub = resultDoc.subdomainName ?? 'Général';
        setState(() {
          _domainSummary[dom] = (_domainSummary[dom] ?? 0) + 1;
          _lastClassifiedBadge = '➔ $dom ($sub)';
          _recentClassified.insert(0, {
            'file': doc.fileName,
            'domain': dom,
            'subdomain': sub,
          });
          if (_recentClassified.length > 5) {
            _recentClassified.removeLast();
          }
        });
      }

      // Petite pause pour fluidité et respecter le débit gratuit
      await Future.delayed(const Duration(milliseconds: 300));
    }

    if (mounted) {
      setState(() {
        _isClassifying = false;
        _isFinished = true;
        _statusMessage = '🎉 Classement terminé avec succès !';
      });
    }
  }

  Future<void> _handleQuotaCooldown(int seconds) async {
    int remaining = seconds;
    final completer = Completer<void>();

    setState(() {
      _quotaWaitSeconds = remaining;
      _statusMessage = 'Pause de $remaining s pour recharge gratuite des quotas $_activeProviderName...';
    });

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _isCancelled) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete();
        return;
      }
      remaining--;
      if (remaining <= 0) {
        timer.cancel();
        setState(() {
          _quotaWaitSeconds = 0;
          _statusMessage = 'Reprise de la classification...';
        });
        if (!completer.isCompleted) completer.complete();
      } else {
        setState(() {
          _quotaWaitSeconds = remaining;
          _statusMessage = 'Pause de $remaining s pour recharge gratuite des quotas $_activeProviderName...';
        });
      }
    });

    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _docsToClassify.length;
    final double progress = total > 0 ? (_currentIndex / total) : 0.0;

    return PopScope(
      canPop: _isFinished || !_isClassifying,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const AppLogo(size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _isFinished
                    ? 'Classement terminé'
                    : (_needsApiKey ? 'Clé API Requise' : 'Classement par IA'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Si besoin de la clé API
                if (_needsApiKey) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.key, color: Colors.blue.shade800, size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              'Entrez votre clé Groq gratuite',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Pour ranger automatiquement vos PDF par thèmes, résumés et sous-domaines, collez votre clé API Groq (ex: gsk_...) :',
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _apiKeyController,
                          obscureText: true,
                          decoration: InputDecoration(
                            hintText: 'gsk_...',
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
                          onPressed: _saveKeyAndStart,
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text('Enregistrer et lancer le classement'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(40),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // 2. Progression active du classement
                if (!_needsApiKey && !_isFinished) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.psychology, size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$_activeProviderName ($_activeModel)',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _statusMessage,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 12),
                  if (total > 0) ...[
                    LinearProgressIndicator(
                      value: progress > 1.0 ? 1.0 : progress,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('$_currentIndex / $total document(s)', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        Text('${(progress * 100).toInt()}%', style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                  if (_currentFileName.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _currentFileName,
                      style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey.shade700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (_lastClassifiedBadge.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Text(
                        _lastClassifiedBadge,
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.green.shade900),
                      ),
                    ),
                  ],
                  if (_quotaWaitSeconds > 0) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.hourglass_top, color: Colors.amber.shade900, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Recharge gratuite en cours ($_quotaWaitSeconds s)...',
                              style: TextStyle(fontSize: 11.5, color: Colors.amber.shade900, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_recentClassified.isNotEmpty) ...[
                    const Divider(height: 20),
                    const Text('Derniers classements :', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    ..._recentClassified.take(3).map((item) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, size: 14, color: Colors.green),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${item['file']}',
                                style: const TextStyle(fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item['domain'] ?? '',
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],

                // 3. Résumé final après succès
                if (_isFinished) ...[
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
                                '$_currentIndex document(s) classé(s) avec succès !',
                                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Colors.green.shade900),
                              ),
                            ),
                          ],
                        ),
                        if (_domainSummary.isNotEmpty) ...[
                          const Divider(height: 16),
                          Text(
                            'Domaines créés / mis à jour (${_domainSummary.length}) :',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade900),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: _domainSummary.entries.map((entry) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.green.shade300),
                                ),
                                child: Text(
                                  '${entry.key} (${entry.value})',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade900),
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
        ),
        actions: [
          if (!_isFinished && !_needsApiKey)
            TextButton(
              onPressed: () {
                _isCancelled = true;
                _countdownTimer?.cancel();
                Navigator.of(context).pop();
                widget.onFinished();
              },
              child: const Text('Arrêter'),
            ),
          if (_needsApiKey)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
          if (_isFinished)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onFinished();
              },
              icon: const Icon(Icons.library_books, size: 18),
              label: const Text('Voir mes domaines'),
            ),
        ],
      ),
    );
  }
}
