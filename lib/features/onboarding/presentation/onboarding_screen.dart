import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/network/groq_api_client.dart';
import '../../../core/storage/secure_storage_service.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onFinished;

  const OnboardingScreen({super.key, required this.onFinished});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Étape 1 : Clé Groq
  final TextEditingController _apiKeyController = TextEditingController();
  bool _isTestingKey = false;
  String? _keyTestMessage;
  bool _isKeyValid = false;

  // Étape 2 : Permissions
  bool _storagePermissionGranted = false;

  // Étape 3 : Confidentialité
  bool _privacyConsentChecked = false;

  @override
  void dispose() {
    _pageController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _testAndSaveApiKey() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) {
      setState(() {
        _keyTestMessage = 'Veuillez saisir votre clé API Groq.';
        _isKeyValid = false;
      });
      return;
    }

    setState(() {
      _isTestingKey = true;
      _keyTestMessage = null;
    });

    final valid = await GroqApiClient.instance.testApiKey(key);

    if (!mounted) return;

    setState(() {
      _isTestingKey = false;
      _isKeyValid = valid;
      _keyTestMessage = valid
          ? 'Connexion réussie avec Groq !'
          : 'Clé invalide ou problème de connexion.';
    });

    if (valid) {
      await SecureStorageService.instance.setGroqApiKey(key);
    }
  }

  Future<void> _requestStoragePermission() async {
    // Demander la permission de gestion de stockage sur Android 11+
    PermissionStatus status;
    if (await Permission.manageExternalStorage.isGranted) {
      status = PermissionStatus.granted;
    } else {
      status = await Permission.manageExternalStorage.request();
      if (!status.isGranted) {
        // Fallback vers les permissions classiques de stockage
        status = await Permission.storage.request();
      }
    }

    if (!mounted) return;

    setState(() {
      _storagePermissionGranted = status.isGranted;
    });

    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('L\'autorisation est nécessaire pour repérer les PDF sur votre appareil.'),
        ),
      );
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
            // Barre de progression des étapes
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: List.generate(3, (index) {
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      height: 6,
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

            // Contenu des 3 étapes
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

  // ==================== ÉTAPE 1 : CLÉ API GROQ ====================
  Widget _buildStep1ApiKey() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.vpn_key_rounded, color: Colors.blue, size: 36),
          ),
          const SizedBox(height: 16),
          const Text(
            'Étape 1 sur 3',
            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          const Text(
            'Configuration de l\'API Groq',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'Pour analyser et classer vos documents PDF à très grande vitesse, l\'application utilise les modèles IA hébergés sur Groq. Votre clé est stockée de manière chiffrée sur votre téléphone.',
            style: TextStyle(fontSize: 14, color: Colors.black87, height: 1.4),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _apiKeyController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Clé API Groq (gsk_...)',
              hintText: 'Collez votre clé ici',
              prefixIcon: const Icon(Icons.key),
              suffixIcon: _isTestingKey
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      icon: const Icon(Icons.check_circle_outline),
                      onPressed: _testAndSaveApiKey,
                      tooltip: 'Tester la clé',
                    ),
            ),
          ),
          const SizedBox(height: 12),
          if (_keyTestMessage != null)
            Row(
              children: [
                Icon(
                  _isKeyValid ? Icons.check_circle : Icons.error,
                  color: _isKeyValid ? Colors.green : Colors.red,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _keyTestMessage!,
                    style: TextStyle(
                      color: _isKeyValid ? Colors.green.shade700 : Colors.red.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _isTestingKey ? null : _testAndSaveApiKey,
            icon: const Icon(Icons.speed),
            label: const Text('Tester et enregistrer la clé'),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Colors.amber, size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Vous pouvez générer gratuitement votre clé API sur console.groq.com. Elle reste strictement confidentielle sur votre mobile.',
                    style: TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isKeyValid
                  ? () => _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      )
                  : null,
              child: const Text('Continuer'),
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
                          style: TextStyle(fontWeight: FontWeight.w600),
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
                          style: TextStyle(fontWeight: FontWeight.w600),
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
            ),
          ),
          const SizedBox(height: 40),
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
                  onPressed: _storagePermissionGranted
                      ? () => _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          )
                      : null,
                  child: const Text('Continuer'),
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
            'Avant d\'initialiser votre bibliothèque, veuillez prendre connaissance des règles de protection de vos données :',
            style: TextStyle(fontSize: 14, color: Colors.black87),
          ),
          const SizedBox(height: 16),
          _buildPrivacyBullet(
            icon: Icons.smartphone,
            text: 'Vos documents PDF restent strictement stockés sur votre téléphone.',
          ),
          _buildPrivacyBullet(
            icon: Icons.short_text,
            text: 'Seul le texte des 3 premières pages est transmis à Groq pour classification.',
          ),
          _buildPrivacyBullet(
            icon: Icons.cached,
            text: 'Les analyses sont mémorisées localement : aucun document n\'est analysé deux fois.',
          ),
          _buildPrivacyBullet(
            icon: Icons.shield_outlined,
            text: 'Vous gardez le contrôle : vous pouvez exclure tout document sensible de l\'analyse IA.',
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
