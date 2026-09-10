import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/network/groq_api_client.dart';
import '../../../core/storage/secure_storage_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _apiKeyController = TextEditingController();
  bool _isTestingKey = false;
  String? _keyTestMessage;
  bool _isKeyValid = false;

  String _selectedModel = AppConstants.groqDefaultModel;
  int _scanPageCount = AppConstants.defaultScanPageCount;
  List<String> _customFolders = [];
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final storage = SecureStorageService.instance;
    final db = DatabaseHelper.instance;

    final key = await storage.getGroqApiKey() ?? '';
    final model = await storage.getSelectedGroqModel();
    final pages = await storage.getScanPageCount();
    final folders = await storage.getCustomScanFolders();
    final stats = await db.getLibraryStats();

    if (!mounted) return;

    setState(() {
      _apiKeyController.text = key;
      _selectedModel = model;
      _scanPageCount = pages;
      _customFolders = folders;
      _stats = stats;
      _isLoading = false;
    });
  }

  Future<void> _saveAndTestApiKey() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) return;

    setState(() {
      _isTestingKey = true;
      _keyTestMessage = null;
    });

    final valid = await GroqApiClient.instance.testApiKey(key);

    if (!mounted) return;

    setState(() {
      _isTestingKey = false;
      _isKeyValid = valid;
      _keyTestMessage = valid ? 'Clé valide et enregistrée !' : 'Clé invalide.';
    });

    if (valid) {
      await SecureStorageService.instance.setGroqApiKey(key);
    }
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres & IA'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 1. STATISTIQUES DE LA BIBLIOTHÈQUE
                _buildSectionHeader('Statistiques de la bibliothèque', Icons.analytics_outlined),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            _buildStatItem('Documents', '${_stats['totalDocs'] ?? 0}', Icons.description),
                            _buildStatItem('Analysés par IA', '${_stats['totalAnalyzed'] ?? 0}', Icons.auto_awesome),
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

                // 2. CONFIGURATION GROQ
                _buildSectionHeader('Configuration Groq API', Icons.vpn_key_outlined),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _apiKeyController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'Clé API Groq',
                            suffixIcon: _isTestingKey
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.check),
                                    onPressed: _saveAndTestApiKey,
                                    tooltip: 'Tester et enregistrer',
                                  ),
                          ),
                        ),
                        if (_keyTestMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _keyTestMessage!,
                            style: TextStyle(
                              color: _isKeyValid ? Colors.green : Colors.red,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        const Text('Modèle de langage utilisé :', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _selectedModel,
                          decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                          items: const [
                            DropdownMenuItem(
                              value: AppConstants.groqDefaultModel,
                              child: Text('Llama 3.3 70B (Recommandé - Très précis)'),
                            ),
                            DropdownMenuItem(
                              value: AppConstants.groqFastModel,
                              child: Text('Llama 3.1 8B (Ultra-rapide)'),
                            ),
                          ],
                          onChanged: (val) async {
                            if (val != null) {
                              setState(() => _selectedModel = val);
                              await SecureStorageService.instance.setSelectedGroqModel(val);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // 3. PARAMÈTRES D'EXTRACTION PDF
                _buildSectionHeader('Extraction & Économie de données', Icons.tune),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Nombre de pages analysées :'),
                            Text(
                              '$_scanPageCount page${_scanPageCount > 1 ? 's' : ''}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                          'Analyser les 3 premières pages suffit dans 95% des cas pour comprendre le contenu tout en économisant les tokens.',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // 4. DOSSIERS SCANNÉS
                _buildSectionHeader('Dossiers personnalisés à scanner', Icons.folder_copy_outlined),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        if (_customFolders.isEmpty)
                          Text(
                            'Les dossiers usuels (Téléchargements, Documents, WhatsApp) sont automatiquement inclus.',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          ),
                        ..._customFolders.map((folder) {
                          return ListTile(
                            leading: const Icon(Icons.folder, color: Colors.amber),
                            title: Text(folder, style: const TextStyle(fontSize: 13)),
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
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
