import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/network/unified_ai_client.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../main.dart';
import 'groq_guide_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _endpointController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();

  String _selectedProvider = AppConstants.providerGroq;
  String _selectedModel = AppConstants.groqDefaultModel;
  bool _isTestingKey = false;
  String? _keyTestMessage;
  bool _isKeyValid = false;

  int _scanPageCount = AppConstants.defaultScanPageCount;
  List<String> _customFolders = [];
  Map<String, dynamic> _stats = {};
  String _selectedTheme = AppConstants.themeClassicWarm;
  bool _autoScanNewDocs = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _endpointController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final storage = SecureStorageService.instance;
      final db = DatabaseHelper.instance;

      final prov = await storage.getActiveProvider();
      final key = await storage.getApiKey(provider: prov) ?? '';
      final model = await storage.getSelectedModel(provider: prov);
      final endpoint = await storage.getCustomEndpoint();
      final pages = await storage.getScanPageCount();
      final folders = await storage.getCustomScanFolders();
      final theme = await storage.getSelectedTheme();
      final autoScan = await storage.isAutoScanEnabled();
      final stats = await db.getLibraryStats();

      if (!mounted) return;

      setState(() {
        _selectedProvider = prov;
        _apiKeyController.text = key;
        _selectedModel = model;
        _modelController.text = model;
        _endpointController.text = endpoint;
        _scanPageCount = pages;
        _customFolders = folders;
        _selectedTheme = theme;
        _autoScanNewDocs = autoScan;
        _stats = stats;
      });
    } catch (e) {
      debugPrint('Error loading settings: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _onProviderChanged(String newProvider) async {
    final storage = SecureStorageService.instance;
    final key = await storage.getApiKey(provider: newProvider) ?? '';
    final model = await storage.getSelectedModel(provider: newProvider);

    setState(() {
      _selectedProvider = newProvider;
      _apiKeyController.text = key;
      _selectedModel = model;
      _modelController.text = model;
      _keyTestMessage = null;
    });

    await storage.setActiveProvider(newProvider);
  }

  void _onKeyChanged(String value) {
    final detected = UnifiedAiClient.detectProviderFromKey(value);
    if (detected != _selectedProvider && value.length >= 4) {
      _onProviderChanged(detected);
    }
  }

  Future<void> _saveAndTestApiKey() async {
    final key = _apiKeyController.text.trim();
    final model = _modelController.text.trim().isNotEmpty
        ? _modelController.text.trim()
        : AppConstants.supportedProviders.firstWhere((p) => p.id == _selectedProvider).defaultModel;
    final storage = SecureStorageService.instance;

    setState(() {
      _selectedModel = model;
      _isTestingKey = true;
      _keyTestMessage = null;
    });

    final res = await UnifiedAiClient.instance.testApiKey(
      provider: _selectedProvider,
      apiKey: key,
      model: model,
      customEndpoint: _endpointController.text.trim(),
    );

    if (!mounted) return;

    setState(() {
      _isTestingKey = false;
      _isKeyValid = res.isValid;
      _testMessageFromResult(res);
    });

    // Enregistrer quoi qu'il arrive si l'utilisateur le souhaite
    await storage.setActiveProvider(_selectedProvider);
    await storage.setApiKey(key, provider: _selectedProvider);
    await storage.setSelectedModel(model, provider: _selectedProvider);
    if (_selectedProvider == AppConstants.providerCustom) {
      await storage.setCustomEndpoint(_endpointController.text.trim());
    }
  }

  void _testMessageFromResult(AiTestResult res) {
    _keyTestMessage = res.message;
  }

  Future<void> _deleteKey() async {
    final storage = SecureStorageService.instance;
    await storage.deleteApiKey(provider: _selectedProvider);
    setState(() {
      _apiKeyController.clear();
      _keyTestMessage = 'Clé supprimée avec succès.';
      _isKeyValid = false;
    });
  }

  Future<void> _addCustomFolder() async {
    final String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory != null) {
      await SecureStorageService.instance.addCustomScanFolder(selectedDirectory);
      _loadSettings();
    }
  }

  Future<void> _removeFolder(String folder) async {
    await SecureStorageService.instance.removeCustomScanFolder(folder);
    _loadSettings();
  }

  String _formatTotalSize(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} Ko';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }

  @override
  Widget build(BuildContext context) {
    final currentProviderInfo = AppConstants.supportedProviders.firstWhere(
      (p) => p.id == _selectedProvider,
      orElse: () => AppConstants.supportedProviders.first,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            AppLogo(size: 26),
            SizedBox(width: 8),
            Text('Paramètres & IA'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 1. STATISTIQUES
                _buildSectionHeader('Statistiques de la bibliothèque', Icons.analytics_outlined),
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            _buildStatItem('Documents', '${_stats['totalDocs'] ?? 0}', Icons.description),
                            _buildStatItem('Analysés IA', '${_stats['totalAnalyzed'] ?? 0}', Icons.auto_awesome),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            _buildStatItem('Domaines', '${_stats['totalDomains'] ?? 0}', Icons.category),
                            _buildStatItem('Espace total', _formatTotalSize(_stats['totalSize'] ?? 0), Icons.storage),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // 2. CONFIGURATION MULTI-IA
                _buildSectionHeader('Intelligence Artificielle & Clé API', Icons.psychology_outlined),
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Guide Groq gratuit
                        InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const GroqGuideScreen()),
                            );
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.help_outline_rounded, color: Colors.blue.shade700, size: 22),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Guide : Obtenir une clé Groq & modèles actifs',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue.shade900,
                                        ),
                                      ),
                                      Text(
                                        'Tutoriel pas à pas gratuit, quotas et choix du modèle.',
                                        style: TextStyle(fontSize: 11, color: Colors.blue.shade800),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.arrow_forward_ios, size: 13, color: Colors.blue.shade700),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        const Text(
                          'Fournisseur d\'IA utilisé :',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _selectedProvider,
                          isExpanded: true,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          items: AppConstants.supportedProviders.map((p) {
                            return DropdownMenuItem<String>(
                              value: p.id,
                              child: Text(p.name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) _onProviderChanged(val);
                          },
                        ),
                        const SizedBox(height: 14),

                        // Champ Clé
                        TextField(
                          controller: _apiKeyController,
                          obscureText: true,
                          onChanged: _onKeyChanged,
                          decoration: InputDecoration(
                            labelText: 'Clé API (${currentProviderInfo.keyHint})',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            suffixIcon: _isTestingKey
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.check),
                                    onPressed: _saveAndTestApiKey,
                                    tooltip: 'Tester et enregistrer',
                                  ),
                          ),
                        ),

                        if (currentProviderInfo.isCustom) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _endpointController,
                            decoration: InputDecoration(
                              labelText: 'URL Endpoint compatible OpenAI',
                              hintText: 'http://localhost:11434/v1/chat/completions',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],

                        if (_keyTestMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _keyTestMessage!,
                            style: TextStyle(
                              color: _isKeyValid ? Colors.green.shade700 : Colors.orange.shade900,
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                            ),
                          ),
                        ],

                        const SizedBox(height: 16),
                        const Text('Modèle de langage (modifiable librement) :', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _modelController,
                          decoration: InputDecoration(
                            labelText: 'Version ou nom du modèle',
                            hintText: currentProviderInfo.defaultModel,
                            prefixIcon: const Icon(Icons.tune),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            helperText: 'Vous pouvez entrer la version exacte souhaitée (ex: ${currentProviderInfo.defaultModel}).',
                          ),
                          onChanged: (val) {
                            setState(() => _selectedModel = val.trim());
                          },
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: currentProviderInfo.availableModels.map((m) {
                              final isSelected = _modelController.text.trim() == m;
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ActionChip(
                                  label: Text(
                                    m,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      color: isSelected ? Colors.blue.shade900 : null,
                                    ),
                                  ),
                                  backgroundColor: isSelected ? Colors.blue.shade100 : null,
                                  onPressed: () async {
                                    setState(() {
                                      _modelController.text = m;
                                      _selectedModel = m;
                                    });
                                    await SecureStorageService.instance.setSelectedModel(m, provider: _selectedProvider);
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),

                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _isTestingKey ? null : _saveAndTestApiKey,
                                icon: const Icon(Icons.save, size: 18),
                                label: const Text('Tester & Sauvegarder', style: TextStyle(fontSize: 13)),
                              ),
                            ),
                            if (_apiKeyController.text.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                tooltip: 'Supprimer la clé',
                                onPressed: _deleteKey,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // 3. THÈMES & COULEURS HUMAINES
                _buildSectionHeader('Thèmes & Ambiance de lecture', Icons.palette_outlined),
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ambiance visuelle soignée et chaleureuse, conçue pour un confort de lecture optimal :',
                          style: TextStyle(fontSize: 12.5, color: Colors.black87),
                        ),
                        const SizedBox(height: 14),
                        ...AppTheme.availableThemes.map((opt) {
                          final isSelected = _selectedTheme == opt.id;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: isSelected ? Theme.of(context).primaryColor : Colors.grey.shade300,
                                width: isSelected ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              color: isSelected
                                  ? Theme.of(context).primaryColor.withOpacity(0.06)
                                  : null,
                            ),
                            child: ListTile(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              leading: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: opt.previewPrimary,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.black12),
                                ),
                                child: Center(
                                  child: Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: opt.previewBackground,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ),
                              title: Text(
                                opt.name,
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                  fontSize: 13.5,
                                ),
                              ),
                              subtitle: Text(
                                opt.description,
                                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                              ),
                              trailing: isSelected
                                  ? Icon(Icons.check_circle, color: Theme.of(context).primaryColor)
                                  : null,
                              onTap: () async {
                                setState(() => _selectedTheme = opt.id);
                                await SecureStorageService.instance.setSelectedTheme(opt.id);
                                if (context.mounted) {
                                  SmartPdfLibraryApp.updateTheme(context, opt.id);
                                }
                              },
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // 4. AUTOMATISATION & 100% HORS-LIGNE
                _buildSectionHeader('Automatisation & Mode Hors-ligne', Icons.auto_mode_outlined),
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: SwitchListTile(
                      title: const Text(
                        'Détection auto des nouveaux PDFs',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text(
                        'Dès qu\'un fichier PDF entre dans le téléphone (WhatsApp, Téléchargements...), il est automatiquement répertorié dès l\'ouverture de l\'application.',
                        style: TextStyle(fontSize: 11.5),
                      ),
                      value: _autoScanNewDocs,
                      onChanged: (val) async {
                        setState(() => _autoScanNewDocs = val);
                        await SecureStorageService.instance.setAutoScanEnabled(val);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.wifi_off_outlined, color: Colors.green.shade700, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Bibliothèque 100% Hors-Ligne',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                                color: Colors.green.shade900,
                              ),
                            ),
                            Text(
                              'Seule la première analyse IA nécessite internet. Une fois vos documents indexés, la recherche plein-texte SQLite, la consultation et la lecture fonctionnent totalement hors-ligne.',
                              style: TextStyle(fontSize: 11, color: Colors.green.shade800),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // 3. PARAMÈTRES D'EXTRACTION PDF
                _buildSectionHeader('Extraction & Économie de données', Icons.tune),
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Pages analysées par document :'),
                            Text(
                              '$_scanPageCount page${_scanPageCount > 1 ? 's' : ''}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ],
                        ),
                        Slider(
                          value: _scanPageCount.toDouble(),
                          min: 1,
                          max: 10,
                          divisions: 9,
                          label: '$_scanPageCount pages',
                          onChanged: (val) async {
                            final count = val.toInt();
                            setState(() => _scanPageCount = count);
                            await SecureStorageService.instance.setScanPageCount(count);
                          },
                        ),
                        Text(
                          'Analyser les 3 premières pages permet un classement précis tout en économisant les quotas.',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // 4. DOSSIERS SCANNÉS
                _buildSectionHeader('Dossiers personnalisés', Icons.folder_copy_outlined),
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        if (_customFolders.isEmpty)
                          Text(
                            'Les dossiers standards (Téléchargements, Documents, WhatsApp) sont automatiquement inclus.',
                            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                          ),
                        ..._customFolders.map((folder) {
                          return ListTile(
                            leading: const Icon(Icons.folder, color: Colors.amber),
                            title: Text(folder, style: const TextStyle(fontSize: 12.5)),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => _removeFolder(folder),
                            ),
                            contentPadding: EdgeInsets.zero,
                          );
                        }),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _addCustomFolder,
                            icon: const Icon(Icons.add),
                            label: const Text('Ajouter un dossier spécifique'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // À propos avec Logo
                const Center(
                  child: AppLogo(size: 44, showText: true),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Version ${AppConstants.appVersion}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).primaryColor),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Expanded(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: Theme.of(context).primaryColor),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
