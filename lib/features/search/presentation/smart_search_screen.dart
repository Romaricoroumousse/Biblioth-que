import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../models/document_model.dart';
import '../../../models/domain_model.dart';
import '../../library/presentation/document_detail_screen.dart';
import '../../library/presentation/widgets/document_card.dart';

class SmartSearchScreen extends StatefulWidget {
  final String? initialQuery;

  const SmartSearchScreen({super.key, this.initialQuery});

  @override
  State<SmartSearchScreen> createState() => _SmartSearchScreenState();
}

class _SmartSearchScreenState extends State<SmartSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<DocumentModel> _results = [];
  List<DomainModel> _allDomains = [];
  bool _isLoading = false;

  // Filtres
  int? _selectedDomainId;
  String? _selectedLevel;
  bool _favoritesOnly = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null) {
      _searchController.text = widget.initialQuery!;
    }
    _loadDomains();
    _performSearch();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDomains() async {
    final domains = await DatabaseHelper.instance.getAllDomainsWithCounts();
    if (mounted) {
      setState(() => _allDomains = domains);
    }
  }

  Future<void> _performSearch() async {
    setState(() => _isLoading = true);

    final results = await DatabaseHelper.instance.searchDocuments(
      query: _searchController.text,
      domainId: _selectedDomainId,
      level: _selectedLevel,
      favoritesOnly: _favoritesOnly,
    );

    if (!mounted) return;

    setState(() {
      _results = results;
      _isLoading = false;
    });
  }

  Future<void> _toggleFavorite(DocumentModel doc) async {
    final updated = doc.copyWith(isFavorite: !doc.isFavorite);
    if (updated.id != null) {
      await DatabaseHelper.instance.toggleFavorite(updated.id!, updated.isFavorite);
    }
    _performSearch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recherche intelligente'),
      ),
      body: Column(
        children: [
          // Barre de recherche
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => _performSearch(),
              decoration: InputDecoration(
                hintText: 'Rechercher un concept, résumé, mot-clé...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _performSearch();
                        },
                      )
                    : null,
              ),
            ),
          ),

          // Ligne des filtres
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                // Filtre Favoris
                FilterChip(
                  avatar: Icon(
                    _favoritesOnly ? Icons.star : Icons.star_border,
                    size: 16,
                    color: _favoritesOnly ? Colors.amber : Colors.grey,
                  ),
                  label: const Text('Favoris'),
                  selected: _favoritesOnly,
                  onSelected: (val) {
                    setState(() => _favoritesOnly = val);
                    _performSearch();
                  },
                ),
                const SizedBox(width: 8),

                // Filtre Niveau
                DropdownButton<String?>(
                  value: _selectedLevel,
                  hint: const Text('Niveau'),
                  underline: const SizedBox(),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Tous les niveaux')),
                    ...AppConstants.academicLevels.map((lvl) {
                      return DropdownMenuItem(
                        value: lvl,
                        child: Text(lvl[0].toUpperCase() + lvl.substring(1)),
                      );
                    }),
                  ],
                  onChanged: (val) {
                    setState(() => _selectedLevel = val);
                    _performSearch();
                  },
                ),
                const SizedBox(width: 8),

                // Filtre Domaine
                DropdownButton<int?>(
                  value: _selectedDomainId,
                  hint: const Text('Domaine'),
                  underline: const SizedBox(),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Tous les domaines')),
                    ..._allDomains.map((d) {
                      return DropdownMenuItem(
                        value: d.id,
                        child: Text(d.name),
                      );
                    }),
                  ],
                  onChanged: (val) {
                    setState(() => _selectedDomainId = val);
                    _performSearch();
                  },
                ),
              ],
            ),
          ),

          const Divider(height: 16),

          // Résultats
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off, size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 16),
                              Text(
                                _searchController.text.isEmpty
                                    ? 'Tapez un mot ou une phrase pour chercher dans tous vos résumés et mots-clés.'
                                    : 'Aucun document ne correspond à cette recherche.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 8,
                                children: [
                                  ActionChip(
                                    label: const Text('ex: machine learning'),
                                    onPressed: () {
                                      _searchController.text = 'machine learning';
                                      _performSearch();
                                    },
                                  ),
                                  ActionChip(
                                    label: const Text('ex: régression'),
                                    onPressed: () {
                                      _searchController.text = 'régression';
                                      _performSearch();
                                    },
                                  ),
                                  ActionChip(
                                    label: const Text('ex: statistique'),
                                    onPressed: () {
                                      _searchController.text = 'statistique';
                                      _performSearch();
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (ctx, index) {
                          final doc = _results[index];
                          return DocumentCard(
                            document: doc,
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => DocumentDetailScreen(
                                    document: doc,
                                    onKeywordTap: (kw) {
                                      _searchController.text = kw;
                                      _performSearch();
                                    },
                                  ),
                                ),
                              );
                              _performSearch();
                            },
                            onFavoriteToggle: () => _toggleFavorite(doc),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
