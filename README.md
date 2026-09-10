# 📚 Bibliothèque PDF Intelligente

Application mobile Android moderne développée avec **Flutter** et propulsée par **Groq IA** (`llama-3.3-70b-versatile` / `llama-3.1-8b-instant`), conçue pour organiser, classifier et retrouver automatiquement tous vos documents PDF grâce à la puissance des modèles de langage et à une base de données locale **SQLite (FTS5)**.

---

## 🌟 Points Clés & Fonctionnalités

1. **Première ouverture & Sécurité (Onboarding en 3 étapes)** :
   - **Configuration Groq** : Saisie et validation instantanée de votre clé API Groq avec stockage chiffré dans le Keystore Android (`flutter_secure_storage`).
   - **Autorisations pédagogiques** : Explications claires des permissions nécessaires pour parcourir vos fichiers PDF.
   - **Confidentialité garantie** : Vos PDF restent à 100% sur votre appareil ; seules les premières pages sont transmises pour l'analyse thématique. Option d'exclusion pour tout document sensible.

2. **Scan & Détection Intelligente** :
   - Parcours automatique des dossiers habituels (`Téléchargements`, `Documents`, `WhatsApp Documents`, etc.) et ajout possible de dossiers personnalisés.
   - Calcul d'empreinte **SHA-256** pour détecter les doublons et éviter toute réanalyse inutile (économie de quota et de batterie).

3. **Classification & Taxonomie Dynamique** :
   - Extraction des 3 premières pages (ajustable de 1 à 10 pages).
   - Inférence ultra-rapide Groq retournant un format JSON strict :
     - **Domaine** (ex: Informatique, Mathématiques, Économie, Médecine...)
     - **Sous-domaine** (ex: Machine Learning, Macroéconomie, Pharmacologie...)
     - **Résumé synthétique** (2 à 3 phrases)
     - **Mots-clés**
     - **Langue** et **Niveau** (débutant, intermédiaire, avancé, recherche).
   - Capacité pour l'IA de proposer de nouvelles catégories avec ajustement manuel possible.

4. **Recherche Intelligente & Instantanée** :
   - Recherche en texte intégral via **SQLite FTS5** sur les résumés, mots-clés, domaines et sous-domaines.
   - Retrouvez un document même si son nom de fichier est quelconque (`WhatsApp_123.pdf`, `cours_final.pdf`).
   - Filtres croisés par domaine, niveau, langue et favoris.

5. **Fiche Document & Consultation** :
   - Fiche complète avec badges thématiques, résumé détaillé et tags cliquables.
   - Ouverture directe du document original dans votre lecteur PDF Android habituel via `open_filex`.
   - Actions rapides : mise en favori, réanalyse par l'IA, modification manuelle de la catégorie, exclusion.

---

## 📁 Structure du Code

```
projet/
├── android/
│   └── app/src/main/AndroidManifest.xml   # Permissions de stockage et réseau
├── lib/
│   ├── main.dart                          # Point d'entrée, thèmes clair/sombre, routage
│   ├── core/
│   │   ├── constants/app_constants.dart   # Modèles Groq, dossiers par défaut, couleurs
│   │   ├── theme/app_theme.dart           # Thème Material 3 élégant
│   │   ├── database/
│   │   │   ├── database_helper.dart       # SQLite relationnel + table virtuelle FTS5
│   │   │   └── default_taxonomies.dart    # Taxonomies prédéfinies
│   │   ├── storage/
│   │   │   └── secure_storage_service.dart# Chiffrement de la clé Groq & préférences
│   │   ├── network/
│   │   │   └── groq_api_client.dart       # Requêtes Groq API, prompts JSON stricts
│   │   └── utils/
│   │       ├── file_hash.dart             # Empreinte SHA-256 optimisée pour gros fichiers
│   │       └── text_sanitizer.dart        # Nettoyage et troncature du texte
│   ├── models/
│   │   ├── document_model.dart            # Modèle Document & mapping BDD
│   │   └── domain_model.dart              # Domaines & sous-domaines
│   ├── services/
│   │   ├── pdf_scanner_service.dart       # Découverte récursive des PDF
│   │   ├── pdf_extractor_service.dart     # Extraction de texte via Syncfusion
│   │   └── ai_classification_service.dart # Orchestration du pipeline d'analyse
│   └── features/
│       ├── onboarding/presentation/       # Écran d'accueil en 3 étapes
│       ├── library/presentation/          # Écran d'accueil, fiche document, détails domaines
│       ├── search/presentation/           # Recherche intelligente FTS5
│       ├── scanner/presentation/          # Boîte de dialogue du scan en direct
│       └── settings/presentation/         # Paramètres, gestion de la clé & statistiques
├── test_pipeline.py                       # Script de test local immédiat (Python)
└── pubspec.yaml                           # Dépendances Flutter
```

---

## 🚀 Démarrage Rapide

### 1. Tester immédiatement le pipeline IA sur votre PC (Python)

Un script de test autonome est inclus à la racine. Il permet de tester l'extraction, la classification Groq et l'indexation SQLite FTS5 directement sur un PDF existant :

```powershell
python test_pipeline.py
```

Vous pouvez renseigner votre clé Groq ou laisser vide pour simuler le comportement.

### 2. Lancer l'application Flutter sur votre smartphone Android

Assurez-vous d'avoir Flutter installé sur votre machine :

```powershell
# 1. Télécharger les dépendances
flutter pub get

# 2. Connecter votre smartphone en mode débogage USB (ou démarrer un émulateur)
flutter devices

# 3. Lancer l'application
flutter run
```

---

## 🔒 Confidentialité & Respect de la vie privée

- Les fichiers PDF ne sont **jamais téléversés** dans le cloud.
- Seul un extrait textuel des 3 premières pages est transmis à l'API Groq pour identifier le sujet.
- L'empreinte SHA-256 évite d'envoyer deux fois le même fichier.
- Un document peut être exclu à tout moment d'un simple clic.
