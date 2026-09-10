import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../models/document_model.dart';
import '../../../models/domain_model.dart';
import 'document_detail_screen.dart';
import 'widgets/document_card.dart';

class DomainDetailScreen extends StatefulWidget {
  final DomainModel domain;

  const DomainDetailScreen({super.key, required this.domain});

  @override
  State<DomainDetailScreen> createState() => _DomainDetailScreenState();
}

class _DomainDetailScreenState extends State<DomainDetailScreen> {
  List<SubdomainModel> _subdomains = [];
  List<DocumentModel> _documents = [];
  int? _selectedSubdomainId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final db = DatabaseHelper.instance;

    final subdomains = await db.getSubdomainsForDomain(widget.domain.id!);
    final documents = await db.getDocumentsForDomain(
      widget.domain.id!,
      subdomainId: _selectedSubdomainId,
    );

    if (!mounted) return;

    setState(() {
      _subdomains = subdomains;
      _documents = documents;
      _isLoading = false;
    });
  }

  void _onSubdomainSelected(int? subdomainId) {
    setState(() {
      _selectedSubdomainId = subdomainId;
    });
    _loadData();
  }

  Future<void> _toggleFavorite(DocumentModel doc) async {
    final updated = doc.copyWith(isFavorite: !doc.isFavorite);
    if (updated.id != null) {
      await DatabaseHelper.instance.toggleFavorite(updated.id!, updated.isFavorite);
    }
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final domainColor = AppConstants.domainColors[widget.domain.name] ?? Colors.indigo;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.domain.name),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // En-tête avec compteur et barre de sous-domaines
                if (_subdomains.isNotEmpty)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        FilterChip(
                          label: Text('Tous (${widget.domain.documentCount})'),
                          selected: _selectedSubdomainId == null,
                          onSelected: (_) => _onSubdomainSelected(null),
                          selectedColor: domainColor.withOpacity(0.2),
                        ),
                        const SizedBox(width: 8),
                        ..._subdomains.map((sub) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text('${sub.name} (${sub.documentCount})'),
                              selected: _selectedSubdomainId == sub.id,
                              onSelected: (_) => _onSubdomainSelected(sub.id),
                              selectedColor: domainColor.withOpacity(0.2),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),

                // Liste des documents
                Expanded(
                  child: _documents.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.folder_open, size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(
                                'Aucun document dans cette catégorie.',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _documents.length,
                          itemBuilder: (ctx, index) {
                            final doc = _documents[index];
                            return DocumentCard(
                              document: doc,
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => DocumentDetailScreen(document: doc),
                                  ),
                                );
                                _loadData();
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
