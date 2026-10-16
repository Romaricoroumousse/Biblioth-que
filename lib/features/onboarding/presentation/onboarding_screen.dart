import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/network/unified_ai_client.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../../../core/widgets/app_logo.dart';
import '../../settings/presentation/groq_guide_screen.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onFinished;

  const OnboardingScreen({super.key, required this.onFinished});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Étape 1 : Fournisseur et Clé IA (Optionnel)
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _endpointController = TextEditingController();
  final TextEditingController _modelController = TextEditingController(
    text: AppConstants.groqDefaultModel,
  );
  String _selectedProvider = AppConstants.providerGroq;
  bool _isTestingKey = false;
  String? _keyTestMessage;
  bool _isKeyValid = false;

  // Étape 2 : Permissions
  bool _storagePermissionGranted = false;

  // Étape 3 : Confidentialité
  bool _privacyConsentChecked = false;

  @override
  void initState() {
    super.initState();
    _loadInitialConfig();
  }

  Future<void> _loadInitialConfig() async {
    final storage = SecureStorageService.instance;
    final prov = await storage.getActiveProvider();
    final key = await storage.getApiKey(provider: prov) ?? '';
    final model = await storage.getSelectedModel(provider: prov);
    final endpoint = await storage.getCustomEndpoint();

    if (!mounted) return;
    setState(() {
      _selectedProvider = prov;
      _apiKeyController.text = key;
      _modelController.text = model;
      _endpointController.text = endpoint;
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _apiKeyController.dispose();
    _endpointController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  void _onProviderChanged(String val) {
    final info = AppConstants.supportedProviders.firstWhere(
      (p) => p.id == val,
      orElse: () => AppConstants.supportedProviders.first,
    );
    setState(() {
      _selectedProvider = val;
      _modelController.text = info.defaultModel;
      _keyTestMessage = null;
    });
  }

  void _onKeyChanged(String val) {
    final detected = UnifiedAiClient.detectProviderFromKey(val);
    if (detected != _selectedProvider && val.length >= 4) {
      _onProviderChanged(detected);
    }
  }

  Future<void> _testAndSaveApiKey() async {
    final key = _apiKeyController.text.trim();
    final model = _modelController.text.trim();
    if (key.isEmpty && _selectedProvider != AppConstants.providerCustom) {
      setState(() {
        _keyTestMessage = 'Veuillez saisir votre clé API.';
        _isKeyValid = false;
      });
      return;
    }

    setState(() {
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
      _keyTestMessage = res.message;
    });

    if (res.isValid) {
      await SecureStorageService.instance.setActiveProvider(_selectedProvider);
      await SecureStorageService.instance.setApiKey(key, provider: _selectedProvider);
      if (model.isNotEmpty) {
        await SecureStorageService.instance.setSelectedModel(model, provider: _selectedProvider);
      }
      if (_selectedProvider == AppConstants.providerCustom) {
        await SecureStorageService.instance.setCustomEndpoint(_endpointController.text.trim());
      }
    }
  }

  Future<void> _saveAndNextPage() async {
    final key = _apiKeyController.text.trim();
    final model = _modelController.text.trim();
    if (key.isNotEmpty) {
      await SecureStorageService.instance.setActiveProvider(_selectedProvider);
      await SecureStorageService.instance.setApiKey(key, provider: _selectedProvider);
    }
    if (model.isNotEmpty) {
      await SecureStorageService.instance.setSelectedModel(model, provider: _selectedProvider);
    }
    if (_selectedProvider == AppConstants.providerCustom) {
      await SecureStorageService.instance.setCustomEndpoint(_endpointController.text.trim());
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _requestStoragePermission() async {
    PermissionStatus status;
    if (await Permission.manageExternalStorage.isGranted) {
      status = PermissionStatus.granted;
    } else {
      status = await Permission.manageExternalStorage.request();
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }
    }

    if (!mounted) return;

    setState(() {
      _storagePermissionGranted = status.isGranted;
    });

    if (!status.isGranted) {
      final shouldOpen = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Autorisation des fichiers requise'),
          content: const Text(
            'Pour détecter vos PDF automatiquement, Android nécessite l\'accès aux fichiers. Souhaitez-vous ouvrir les paramètres pour l\'activer ?',
            style: TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Plus tard'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ouvrir les Paramètres'),
            ),
          ],
        ),
      );

      if (shouldOpen == true) {
        await openAppSettings();
      }
    }
  }

  Future<void> _finishOnboarding() async {
    if (!_privacyConsentChecked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez accepter les conditions de confidentialité pour continuer.'),
        ),
      );
      return;
    }

    await SecureStorageService.instance.setPrivacyAccepted(true);
    await SecureStorageService.instance.setOnboardingCompleted(true);
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Barre supérieure avec logo
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Row(
                children: [
                  const AppLogo(size: 32),
                  const SizedBox(width: 10),
                  Text(
                    AppConstants.appName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const Spacer(),
                  Text(
                    '${_currentPage + 1} / 3',
                    style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ],
              ),
            ),

            // Barre de progression
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: List.generate(3, (index) {
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      height: 5,
                      decoration: BoxDecoration(
                        color: index <= _currentPage
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // Contenu
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                children: [
                  _buildStep1ApiKey(),
                  _buildStep2Permissions(),
                  _buildStep3Privacy(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== ÉTAPE 1 : CLÉ API MULTI-IA ====================
  Widget _buildStep1ApiKey() {
    final currentProviderInfo = AppConstants.supportedProviders.firstWhere(
      (p) => p.id == _selectedProvider,
      orElse: () => AppConstants.supportedProviders.first,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: AppLogo(size: 64, showText: false),
          ),
          const SizedBox(height: 16),
          const Text(
            'Étape 1 sur 3 (Optionnelle)',
            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 4),
          const Text(
            'Fournisseur d\'IA & Clé API',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'L\'application prend en charge n\'importe quelle IA (Groq, Google Gemini, OpenAI ChatGPT, DeepSeek, Mistral, OpenRouter ou Ollama local).',
            style: TextStyle(fontSize: 13, color: Colors.black87, height: 1.4),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GroqGuideScreen()),
              );
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.help_outline_rounded, color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tutoriel gratuit : Créer un compte Groq & obtenir une clé',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios, size: 12, color: Colors.blue.shade700),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Sélecteur de fournisseur
          DropdownButtonFormField<String>(
            value: _selectedProvider,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Choisissez votre IA',
              prefixIcon: const Icon(Icons.psychology),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: AppConstants.supportedProviders.map((p) {
              return DropdownMenuItem<String>(
                value: p.id,
                child: Text(p.name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                _onProviderChanged(val);
              }
            },
          ),
          const SizedBox(height: 14),

          // Saisie de clé
          TextField(
            controller: _apiKeyController,
            obscureText: true,
            onChanged: _onKeyChanged,
            decoration: InputDecoration(
              labelText: 'Clé API (${currentProviderInfo.keyHint})',
              hintText: 'Collez votre clé ici',
              prefixIcon: const Icon(Icons.vpn_key_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              suffixIcon: _isTestingKey
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : IconButton(
                      icon: const Icon(Icons.check_circle_outline),
                      onPressed: _testAndSaveApiKey,
                      tooltip: 'Tester la clé',
                    ),
            ),
          ),

          const SizedBox(height: 12),

          // Modèle IA personnalisable
          TextField(
            controller: _modelController,
            decoration: InputDecoration(
              labelText: 'Modèle IA (modifiable librement)',
              hintText: currentProviderInfo.defaultModel,
              prefixIcon: const Icon(Icons.tune),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              helperText: 'Vous pouvez sélectionner une suggestion ou taper le modèle de votre choix.',
            ),
          ),
          const SizedBox(height: 6),

          // Suggestions en 1 clic
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
                    onPressed: () {
                      setState(() {
                        _modelController.text = m;
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          if (currentProviderInfo.isCustom) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _endpointController,
              decoration: InputDecoration(
                labelText: 'URL de l\'API compatible OpenAI',
                hintText: 'http://localhost:11434/v1/chat/completions',
                prefixIcon: const Icon(Icons.link),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],

          if (_keyTestMessage != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _isKeyValid ? Icons.check_circle : Icons.info_outline,
                  color: _isKeyValid ? Colors.green : Colors.orange.shade800,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _keyTestMessage!,
                    style: TextStyle(
                      color: _isKeyValid ? Colors.green.shade700 : Colors.orange.shade900,
                      fontWeight: FontWeight.w500,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _isTestingKey ? null : _testAndSaveApiKey,
            icon: const Icon(Icons.speed, size: 18),
            label: const Text('Tester la clé'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(42),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),

          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline, color: Colors.amber, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Vous pouvez passer cette étape dès maintenant ! Vous pourrez renseigner votre clé avant de lancer le scan ou dans les paramètres.',
                    style: TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // Boutons d'action
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saveAndNextPage,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Continuer', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => _pageController.nextPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              ),
              child: const Text('Passer cette étape (Configurer plus tard)', style: TextStyle(color: Colors.grey)),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== ÉTAPE 2 : AUTORISATIONS ====================
  Widget _buildStep2Permissions() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.folder_open_rounded, color: Colors.teal, size: 36),
          ),
          const SizedBox(height: 16),
          const Text(
            'Étape 2 sur 3',
            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          const Text(
            'Accès à vos fichiers',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'Pour constituer automatiquement votre bibliothèque, l\'application a besoin d\'accéder à votre stockage afin de rechercher et lire les documents PDF.',
            style: TextStyle(fontSize: 14, color: Colors.black87, height: 1.4),
          ),
          const SizedBox(height: 24),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.find_in_page_outlined, color: Colors.blue),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Rechercher les fichiers PDF (Téléchargements, WhatsApp, Documents...)',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                      Icon(
                        _storagePermissionGranted ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: _storagePermissionGranted ? Colors.green : Colors.grey,
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    children: [
                      const Icon(Icons.visibility_outlined, color: Colors.teal),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Lire les premières pages pour extraire le sujet et générer le résumé',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                      Icon(
                        _storagePermissionGranted ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: _storagePermissionGranted ? Colors.green : Colors.grey,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _requestStoragePermission,
              icon: Icon(_storagePermissionGranted ? Icons.check : Icons.lock_open),
              label: Text(_storagePermissionGranted
                  ? 'Autorisations accordées'
                  : 'Accorder l\'accès aux fichiers'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => _pageController.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  ),
                  child: const Text('Retour'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _pageController.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(_storagePermissionGranted ? 'Continuer' : 'Passer cette étape'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== ÉTAPE 3 : CONFIDENTIALITÉ ====================
  Widget _buildStep3Privacy() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.security_rounded, color: Colors.indigo, size: 36),
          ),
          const SizedBox(height: 16),
          const Text(
            'Étape 3 sur 3',
            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          const Text(
            'Engagements de confidentialité',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'Avant d\'initialiser votre bibliothèque, prenez connaissance des règles de protection de vos données :',
            style: TextStyle(fontSize: 14, color: Colors.black87),
          ),
          const SizedBox(height: 16),
          _buildPrivacyBullet(
            icon: Icons.smartphone,
            text: 'Vos documents PDF restent strictement stockés sur votre téléphone.',
          ),
          _buildPrivacyBullet(
            icon: Icons.short_text,
            text: 'Seul le texte des 3 premières pages est envoyé au modèle IA pour classification.',
          ),
          _buildPrivacyBullet(
            icon: Icons.cached,
            text: 'Les analyses sont mémorisées localement : aucun document n\'est analysé deux fois.',
          ),
          _buildPrivacyBullet(
            icon: Icons.shield_outlined,
            text: 'Vous gardez le contrôle total : possibilité de scanner sans IA à 100% hors-ligne.',
          ),
          const SizedBox(height: 24),
          CheckboxListTile(
            value: _privacyConsentChecked,
            onChanged: (val) {
              setState(() {
                _privacyConsentChecked = val ?? false;
              });
            },
            title: const Text(
              'J\'ai compris et j\'accepte les conditions de confidentialité et d\'analyse.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => _pageController.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  ),
                  child: const Text('Retour'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _privacyConsentChecked ? _finishOnboarding : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Commencer'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyBullet({required IconData icon, required String text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.indigo),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}
