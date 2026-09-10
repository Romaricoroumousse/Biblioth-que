import 'package:flutter/material.dart';
import '../../../core/database/database_helper.dart';
import '../../../models/document_model.dart';
import '../../../models/domain_model.dart';
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

class _HomeLibraryScreenState extends State<HomeLibraryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<DomainModel> _domains = [];
  List<DocumentModel> _recentDocs = [];
  List<DocumentModel> _favoriteDocs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadLibraryData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadLibraryData() async {
    setState(() => _isLoading = true);
    final db = DatabaseHelper.instance;

    final domains = await db.getAllDomainsWithCounts();
    final recents = await db.getRecentDocuments(limit: 25);
    final favorites = await db.getFavoriteDocuments();

    if (!mounted) return;

    setState(() {
      _domains = domains;
      _recentDocs = recents;
      _favoriteDocs = favorites;
      _isLoading = false;
    });
  }

  void _triggerScanDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ScanProgressDialog(
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
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.auto_stories, color: Color(0xFF1E3A8A)),
            SizedBox(width: 8),
            Text(
              'Ma Bibliothèque',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
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
            tooltip: 'Paramètres',
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
          labelColor: Theme.of(context).primaryColor,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Theme.of(context).primaryColor,
          tabs: const [
            Tab(text: 'Domaines', icon: Icon(Icons.category_outlined)),
            Tab(text: 'Récents', icon: Icon(Icons.history)),
            Tab(text: 'Favoris', icon: Icon(Icons.star_border)),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadLibraryData,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildDomainsTab(),
                  _buildRecentsTab(),
                  _buildFavoritesTab(),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _triggerScanDialog,
        icon: const Icon(Icons.sync),
        label: const Text('Scanner les PDF'),
      ),
    );
  }

  // ==================== ONGLET 1 : DOMAINES ====================
  Widget _buildDomainsTab() {
    // Filtrer les domaines qui ont au moins 1 document, ou afficher les principaux
    final activeDomains = _domains.where((d) => d.documentCount > 0).toList();

    if (activeDomains.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.folder_copy_outlined, size: 72, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text(
                'Votre bibliothèque est vide',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Lancez le premier scan pour détecter et classer automatiquement les PDF de votre téléphone avec Groq IA.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, height: 1.4),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _triggerScanDialog,
                icon: const Icon(Icons.sync),
                label: const Text('Lancer le premier scan'),
              ),
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
      return const Center(
        child: Text('Aucun document récemment consulté.'),
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
            Icon(Icons.star_border, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'Aucun document favori pour le moment.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
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
