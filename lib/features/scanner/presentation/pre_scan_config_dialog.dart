import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/network/unified_ai_client.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../../../core/widgets/app_logo.dart';

class PreScanConfigDialog extends StatefulWidget {
  const PreScanConfigDialog({super.key});

  @override
  State<PreScanConfigDialog> createState() => _PreScanConfigDialogState();
}

class _PreScanConfigDialogState extends State<PreScanConfigDialog> {
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _endpointController = TextEditingController();
  String _selectedProvider = AppConstants.providerGroq;
  bool _isTesting = false;
  String? _testMessage;
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentConfig();
  }

  Future<void> _loadCurrentConfig() async {
    final storage = SecureStorageService.instance;
    final prov = await storage.getActiveProvider();
    final key = await storage.getApiKey(provider: prov) ?? '';
    final endpoint = await storage.getCustomEndpoint();

    if (!mounted) return;
    setState(() {
      _selectedProvider = prov;
      _keyController.text = key;
      _endpointController.text = endpoint;
    });
  }

  @override
  void dispose() {
    _keyController.dispose();
    _endpointController.dispose();
    super.dispose();
  }

  void _onKeyChanged(String value) {
    // Détection automatique du fournisseur
    final detected = UnifiedAiClient.detectProviderFromKey(value);
    if (detected != _selectedProvider && value.length >= 4) {
      setState(() {
        _selectedProvider = detected;
      });
    }
  }

  Future<void> _testKey() async {
    final key = _keyController.text.trim();
    if (key.isEmpty && _selectedProvider != AppConstants.providerCustom) {
      setState(() {
        _testMessage = 'Veuillez saisir votre clé API.';
        _isSuccess = false;
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _testMessage = null;
    });

    final res = await UnifiedAiClient.instance.testApiKey(
      provider: _selectedProvider,
      apiKey: key,
      customEndpoint: _endpointController.text.trim(),
    );

    if (!mounted) return;

    setState(() {
      _isTesting = false;
      _isSuccess = res.isValid;
      _testMessage = res.message;
    });
  }

  Future<void> _saveAndProceed() async {
    final key = _keyController.text.trim();
    final storage = SecureStorageService.instance;

    await storage.setActiveProvider(_selectedProvider);
    if (key.isNotEmpty) {
      await storage.setApiKey(key, provider: _selectedProvider);
    }
    if (_selectedProvider == AppConstants.providerCustom) {
      await storage.setCustomEndpoint(_endpointController.text.trim());
    }

    if (!mounted) return;
    Navigator.of(context).pop(true); // Signale de continuer le scan
  }

  void _proceedWithoutAi() {
    Navigator.of(context).pop(true); // Lancer le scan en mode local
  }

  @override
  Widget build(BuildContext context) {
    final currentProviderInfo = AppConstants.supportedProviders.firstWhere(
      (p) => p.id == _selectedProvider,
      orElse: () => AppConstants.supportedProviders.first,
    );

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      actionsPadding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      title: Row(
        children: [
          const AppLogo(size: 36),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Configuration de l\'IA',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Optionnel avant le scan',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pour analyser et résumer automatiquement vos PDF, choisissez votre service IA :',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 14),

            // Sélecteur de fournisseur
            DropdownButtonFormField<String>(
              value: _selectedProvider,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Fournisseur d\'IA',
                prefixIcon: const Icon(Icons.psychology_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: AppConstants.supportedProviders.map((p) {
                return DropdownMenuItem<String>(
                  value: p.id,
                  child: Text(p.name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedProvider = val;
                    _testMessage = null;
                  });
                }
              },
            ),

            const SizedBox(height: 12),

            // Champ clé API
            TextField(
              controller: _keyController,
              obscureText: true,
              onChanged: _onKeyChanged,
              decoration: InputDecoration(
                labelText: 'Clé API (${currentProviderInfo.keyHint})',
                hintText: 'Collez votre clé ici',
                prefixIcon: const Icon(Icons.key),
                suffixIcon: _isTesting
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(
                        icon: const Icon(Icons.check_circle_outline),
                        onPressed: _testKey,
                        tooltip: 'Tester la clé',
                      ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),

            if (currentProviderInfo.isCustom) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _endpointController,
                decoration: InputDecoration(
                  labelText: 'URL Endpoint compatible OpenAI',
                  hintText: 'http://localhost:11434/v1/chat/completions',
                  prefixIcon: const Icon(Icons.link),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],

            if (_testMessage != null) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _isSuccess ? Icons.check_circle : Icons.info_outline,
                    color: _isSuccess ? Colors.green : Colors.orange.shade800,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _testMessage!,
                      style: TextStyle(
                        fontSize: 12,
                        color: _isSuccess ? Colors.green.shade800 : Colors.orange.shade900,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isTesting ? null : _testKey,
              icon: const Icon(Icons.speed, size: 18),
              label: const Text('Tester la connexion', style: TextStyle(fontSize: 13)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(40),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),

            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.offline_bolt_outlined, color: Colors.blue, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Pas de clé ? Vous pouvez quand même scanner vos PDF sans IA ! Vos documents seront rangés et lisibles immédiatement.',
                      style: TextStyle(fontSize: 11.5, color: Colors.blueGrey),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: _proceedWithoutAi,
                child: const Text('Scanner sans IA', style: TextStyle(fontSize: 13)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: _saveAndProceed,
                child: const Text('Valider & Scanner', style: TextStyle(fontSize: 13)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
