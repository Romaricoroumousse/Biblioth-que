import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/app_logo.dart';

class GroqGuideScreen extends StatelessWidget {
  const GroqGuideScreen({super.key});

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copié dans le presse-papier !'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Guide : Clé & Modèles Groq IA'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // En-tête chaleureux
          Card(
            color: theme.colorScheme.primary.withOpacity(0.08),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  const AppLogo(size: 44, showText: false),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Groq IA Gratuit',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Obtenez votre clé en 2 minutes sans carte bancaire et classez vos livres automatiquement.',
                          style: TextStyle(fontSize: 12.5, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ÉTAPE 1
          _buildStepCard(
            context,
            stepNumber: '1',
            title: 'Créer un compte sur console.groq.com',
            content:
                'Rendez-vous sur le site officiel de Groq. Vous pouvez vous inscrire gratuitement en 1 clic avec votre compte Google ou GitHub.',
            actionLabel: 'Copier l\'adresse du site : console.groq.com',
            onAction: () => _copyToClipboard(context, 'https://console.groq.com', 'Lien'),
            icon: Icons.person_add_alt_1_rounded,
          ),

          const SizedBox(height: 16),

          // ÉTAPE 2
          _buildStepCard(
            context,
            stepNumber: '2',
            title: 'Générer votre Clé API',
            content:
                '1. Dans le menu de gauche, cliquez sur "API Keys".\n'
                '2. Cliquez sur le bouton orange "Create API Key".\n'
                '3. Donnez un nom (ex: "Bibliotheque") et validez.\n'
                '4. Copiez la clé générée (elle commence par "gsk_...").',
            actionLabel: 'Copier le lien des clés : console.groq.com/keys',
            onAction: () => _copyToClipboard(context, 'https://console.groq.com/keys', 'Lien'),
            icon: Icons.key_rounded,
          ),

          const SizedBox(height: 16),

          // ÉTAPE 3
          _buildStepCard(
            context,
            stepNumber: '3',
            title: 'Choisir un modèle à jour',
            content:
                'Les modèles évoluent régulièrement. Voici les modèles recommandés et fonctionnels à ce jour :',
            customWidget: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                _buildModelChoiceRow(
                  context,
                  modelName: 'meta-llama/llama-4-scout-17b-16e-instruct',
                  badge: 'Recommandé & Moderne',
                  description: 'Très intelligent, idéal pour analyser et classer les livres complexes.',
                ),
                const SizedBox(height: 10),
                _buildModelChoiceRow(
                  context,
                  modelName: 'llama-3.1-8b-instant',
                  badge: 'Ultra-rapide',
                  description: 'Consomme très peu de tokens par minute, parfait pour les gros volumes.',
                ),
              ],
            ),
            actionLabel: 'Copier le lien des modèles : console.groq.com/docs/models',
            onAction: () => _copyToClipboard(context, 'https://console.groq.com/docs/models', 'Lien'),
            icon: Icons.tune_rounded,
          ),

          const SizedBox(height: 16),

          // ÉTAPE 4 : COMPRENDRE LES TOKENS
          _buildStepCard(
            context,
            stepNumber: '4',
            title: 'Comment fonctionnent les Tokens gratuits ?',
            content:
                '• Le compte gratuit de Groq offre des milliers de tokens par minute (TPM).\n'
                '• Si vous analysez beaucoup de documents d\'un coup, la limite par minute peut être atteinte (Erreur 429).\n'
                '• Pas de panique : vos tokens se régénèrent AUTOMATIQUEMENT chaque minute !\n'
                '• L\'application classe immédiatement vos documents localement pour que vous puissiez les lire hors-ligne, et vous propose de reprendre l\'analyse IA dès que vos tokens sont rechargés.',
            icon: Icons.battery_charging_full_rounded,
          ),

          const SizedBox(height: 24),

          // Bouton retour
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('J\'ai compris, revenir à la bibliothèque'),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildStepCard(
    BuildContext context, {
    required String stepNumber,
    required String title,
    required String content,
    String? actionLabel,
    VoidCallback? onAction,
    Widget? customWidget,
    required IconData icon,
  }) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: theme.colorScheme.primary,
                  child: Text(
                    stepNumber,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                  ),
                ),
                Icon(icon, color: theme.colorScheme.primary.withOpacity(0.7), size: 22),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              content,
              style: TextStyle(fontSize: 13.5, color: Colors.grey.shade800, height: 1.45),
            ),
            if (customWidget != null) customWidget,
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.copy, size: 16),
                label: Text(actionLabel, style: const TextStyle(fontSize: 12.5)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModelChoiceRow(
    BuildContext context, {
    required String modelName,
    required String badge,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badge,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.green.shade900),
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () => _copyToClipboard(context, modelName, 'Nom du modèle'),
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    children: [
                      Icon(Icons.copy, size: 14, color: Colors.blueGrey),
                      SizedBox(width: 4),
                      Text('Copier', style: TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            modelName,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            description,
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
