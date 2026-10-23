import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../models/document_model.dart';
import '../../../models/domain_model.dart';
import '../../../services/ai_classification_service.dart';
import '../../../services/pdf_scanner_service.dart';
import '../../scanner/presentation/ai_classification_dialog.dart';
import '../../scanner/presentation/pre_scan_config_dialog.dart';
import '../../scanner/presentation/scan_dialog.dart';
import '../../search/presentation/smart_search_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import 'document_detail_screen.dart';
import 'domain_detail_screen.dart';
import 'widgets/document_card.dart';
import 'widgets/domain_card.dart';

class HomeLibraryScreen extends StatefulWidget {
  const HomeLibraryScreen({super.key});

  @override
  State<HomeLibraryScreen> createState() => _HomeLibraryScreenState();
}

class _HomeLibraryScreenState extends State<HomeLibraryScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  List<DomainModel> _domains = [];
  List<DocumentModel> _recentDocs = [];
  List<DocumentModel> _favoriteDocs = [];
  int _pendingCount = 0;
  bool _isLoading = true;
  bool _isAutoScanning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 3, vsync: this);
    _loadLibraryData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Détection automatique des nouveaux documents reçus (ex: WhatsApp, Téléchargements)
      _quickAutoScanNewDocuments();
    }
  }

  /// Détection silencieuse en arrière-plan des nouveaux documents PDF
  Future<void> _quickAutoScanNewDocuments() async {
    final enabled = await SecureStorageService.instance.isAutoScanEnabled();
    if (!enabled || _isAutoScanning) return;

    _isAutoScanning = true;
    try {
      final files = await PdfScannerService.instance.discoverPdfFiles();
      if (files.isEmpty) return;

      final candidates = await PdfScannerService.instance.inspectFiles(files);
      final newCandidates = candidates.where((c) => !c.isAlreadyIndexed).toList();

      if (newCandidates.isNotEmpty) {
        final hasKey = await SecureStorageService.instance.hasApiKey();
        for (final item in newCandidates) {
          try {
            if (hasKey) {
              await AiClassificationService.instance.processSingleFile(
                file: item.file,
                fileHash: item.fileHash,
              );
            } else {
              await AiClassificationService.instance.processSingleFileLocal(
                file: item.file,
                fileHash: item.fileHash,
              );
            }
          } catch (_) {
            try {
              await AiClassificationService.instance.processSingleFileLocal(
                file: item.file,
                fileHash: item.fileHash,
              );
            } catch (_) {}
          }
        }
        if (mounted) {
          _loadLibraryData();
        }
      }
    } catch (_) {
    } finally {
      _isAutoScanning = false;
    }
  }

  Future<void> _loadLibraryData() async {
    setState(() => _isLoading = true);
    try {
      final db = DatabaseHelper.instance;

      final domains = await db.getAllDomainsWithCounts();
      final recents = await db.getRecentDocuments(limit: 25);
      final favorites = await db.getFavoriteDocuments();
      final pending = await db.countPendingDocuments();

      if (!mounted) return;

      setState(() {
        _domains = domains;
        _recentDocs = recents;
        _favoriteDocs = favorites;
        _pendingCount = pending;
      });
    } catch (e, stack) {
      debugPrint('Erreur chargement bibliothèque: $e\n$stack');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<bool> _ensureStoragePermission() async {
    if (!Platform.isAndroid) return true;

    if (await Permission.manageExternalStorage.isGranted) return true;

    final status = await Permission.manageExternalStorage.request();
    if (status.isGranted) return true;

    final legacy = await Permission.storage.request();
    if (legacy.isGranted) return true;

    if (!mounted) return false;

    // Si Android refuse la permission automatique, afficher le dialogue explicatif
    final bool? shouldOpenSettings = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.folder_shared_outlined, color: Colors.amber, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text('Autorisation requise', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pour analyser et classer les livres PDF de votre téléphone, Android demande d\'activer l\'accès aux fichiers.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            SizedBox(height: 12),
            Text(
              'Dans l\'écran qui va s\'ouvrir, cochez simplement "Autoriser la gestion de tous les fichiers".',
              style: TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Choisir manuellement'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ouvrir les Paramètres'),
          ),
        ],
      ),
    );

    if (shouldOpenSettings == true) {
      await openAppSettings();
      return true;
    }

    return false;
  }

  /// Déclenche le scan : vérifie les permissions de stockage et propose la config si nécessaire
  Future<void> _handleScanRequest() async {
    final hasPerm = await _ensureStoragePermission();
    if (!hasPerm) {
      // Si la permission n'est pas accordée, proposer le sélecteur manuel de fichiers
      _pickAndScanCustomFiles();
      return;
    }

    // Vérification de la clé IA
    final hasKey = await SecureStorageService.instance.hasApiKey();
    if (!hasKey) {
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => const PreScanConfigDialog(),
      );

      if (proceed != true) return;
    }

    _triggerScanDialog();
  }

  Future<void> _pickAndScanCustomFiles() async {
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
        final hasKey = await SecureStorageService.instance.hasApiKey();
        if (!hasKey) {
          if (!mounted) return;
          final proceed = await showDialog<bool>(
            context: context,
            builder: (ctx) => const PreScanConfigDialog(),
          );
          if (proceed != true) return;
        }

        _triggerScanDialog(initialFiles: selected);
      }
    }
  }

  void _triggerScanDialog({List<File>? initialFiles}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ScanProgressDialog(
        initialFiles: initialFiles,
        onFinished: () {
          _loadLibraryData();
        },
      ),
    );
  }

  void _triggerAiClassificationDialog({List<DocumentModel>? targetDocs}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AiClassificationDialog(
        targetDocuments: targetDocs,
        onFinished: () {
          _loadLibraryData();
        },
      ),
    );
  }

  Future<void> _toggleFavorite(DocumentModel doc) async {
    final updated = doc.copyWith(isFavorite: !doc.isFavorite);
    if (updated.id != null) {
      await DatabaseHelper.instance.toggleFavorite(updated.id!, updated.isFavorite);
    }
    _loadLibraryData();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            AppLogo(size: 32),
            SizedBox(width: 10),
            Text(
              'Ma Bibliothèque',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: _pendingCount > 0,
              label: Text('$_pendingCount'),
              backgroundColor: Colors.amber.shade900,
              child: const Icon(Icons.auto_awesome_rounded),
            ),
            tooltip: 'Classer les PDF avec l\'IA',
            onPressed: () => _triggerAiClassificationDialog(),
          ),
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: 'Recherche intelligente',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SmartSearchScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Paramètres & Thème',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
              _loadLibraryData();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: Colors.grey,
          indicatorColor: theme.colorScheme.primary,
          tabs: const [
            Tab(text: 'Domaines', icon: Icon(Icons.category_outlined)),
            Tab(text: 'Récents', icon: Icon(Icons.history_rounded)),
            Tab(text: 'Favoris', icon: Icon(Icons.star_border_rounded)),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _quickAutoScanNewDocuments();
                await _loadLibraryData();
              },
              child: Column(
                children: [
                  // Bandeau héroïque bien visible quand des documents sont en attente de classement IA
                  if (_pendingCount > 0)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            theme.colorScheme.primary.withOpacity(0.12),
                            theme.colorScheme.secondary.withOpacity(0.06),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.auto_awesome, color: theme.colorScheme.primary, size: 22),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '$_pendingCount document(s) répertorié(s) prêt(s) pour l\'IA',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.5,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Vos documents sont répertoriés. Cliquez ci-dessous pour lancer l\'analyse IA et créer vos domaines thématiques automatiquement.',
                            style: TextStyle(fontSize: 12, color: Colors.black87),
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton.icon(
                            onPressed: () => _triggerAiClassificationDialog(),
                            icon: const Icon(Icons.psychology, size: 18),
                            label: Text(
                              'Classer maintenant avec l\'IA ($_pendingCount)',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(42),
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                    ),

                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildDomainsTab(),
                        _buildRecentsTab(),
                        _buildFavoritesTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _handleScanRequest,
        icon: const Icon(Icons.sync_rounded),
        label: const Text('Scanner les PDF'),
      ),
    );
  }

  // ==================== ONGLET 1 : DOMAINES ====================
  Widget _buildDomainsTab() {
    final activeDomains = _domains.where((d) => d.documentCount > 0).toList();

    if (activeDomains.isEmpty) {
      final hasDocs = _recentDocs.isNotEmpty || _pendingCount > 0;
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const AppLogo(size: 76),
              const SizedBox(height: 20),
              Text(
                hasDocs
                    ? '${_recentDocs.length} PDF répertorié(s)'
                    : 'Votre bibliothèque est prête',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                hasDocs
                    ? 'Vos documents PDF sont enregistrés dans votre bibliothèque.\nCliquez sur "Classer avec l\'IA" pour créer vos domaines thématiques automatiquement.'
                    : 'Rangez, organisez et retrouvez tous vos livres et cours PDF en un clin d\'œil.\nL\'application fonctionne 100% hors-ligne après classement !',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700, height: 1.45, fontSize: 13.5),
              ),
              const SizedBox(height: 24),
              if (hasDocs) ...[
                ElevatedButton.icon(
                  onPressed: () => _triggerAiClassificationDialog(),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('✨ Classer avec l\'IA maintenant'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _handleScanRequest,
                  icon: const Icon(Icons.sync_rounded),
                  label: const Text('Re-scanner les dossiers'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ] else ...[
                ElevatedButton.icon(
                  onPressed: _handleScanRequest,
                  icon: const Icon(Icons.sync_rounded),
                  label: const Text('Détecter et répertorier mes PDF'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickAndScanCustomFiles,
                  icon: const Icon(Icons.file_upload_outlined),
                  label: const Text('Sélectionner des PDF manuellement'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: activeDomains.length,
      itemBuilder: (ctx, index) {
        final domain = activeDomains[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: DomainCard(
            domain: domain,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DomainDetailScreen(domain: domain),
                ),
              );
              _loadLibraryData();
            },
          ),
        );
      },
    );
  }

  // ==================== ONGLET 2 : RÉCENTS ====================
  Widget _buildRecentsTab() {
    if (_recentDocs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_rounded, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'Aucun document récemment consulté.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _recentDocs.length,
      itemBuilder: (ctx, index) {
        final doc = _recentDocs[index];
        return DocumentCard(
          document: doc,
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DocumentDetailScreen(document: doc),
              ),
            );
            _loadLibraryData();
          },
          onFavoriteToggle: () => _toggleFavorite(doc),
        );
      },
    );
  }

  // ==================== ONGLET 3 : FAVORIS ====================
  Widget _buildFavoritesTab() {
    if (_favoriteDocs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.star_border_rounded, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'Aucun document favori pour le moment.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              'Touchez l\'étoile sur un livre pour le retrouver ici rapidement.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12.5),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _favoriteDocs.length,
      itemBuilder: (ctx, index) {
        final doc = _favoriteDocs[index];
        return DocumentCard(
          document: doc,
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DocumentDetailScreen(document: doc),
              ),
            );
            _loadLibraryData();
          },
          onFavoriteToggle: () => _toggleFavorite(doc),
        );
      },
    );
  }
}
