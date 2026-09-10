import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../models/domain_model.dart';

class DomainCard extends StatelessWidget {
  final DomainModel domain;
  final VoidCallback onTap;

  const DomainCard({
    super.key,
    required this.domain,
    required this.onTap,
  });

  IconData _getDomainIcon(String domainName) {
    switch (domainName) {
      case 'Informatique':
      case 'Programmation':
        return Icons.computer;
      case 'Intelligence Artificielle':
        return Icons.psychology;
      case 'Data Science':
        return Icons.analytics;
      case 'Mathématiques':
      case 'Statistiques':
        return Icons.functions;
      case 'Économie':
      case 'Finance':
        return Icons.trending_up;
      case 'Droit':
        return Icons.gavel;
      case 'Médecine':
        return Icons.medical_services;
      case 'Physique':
        return Icons.bolt;
      case 'Chimie':
        return Icons.science;
      case 'Agriculture':
        return Icons.grass;
      case 'Gestion':
      case 'Comptabilité':
        return Icons.account_balance;
      case 'Sciences Sociales':
        return Icons.groups;
      case 'Éducation':
        return Icons.school;
      case 'Littérature':
      case 'Langues':
        return Icons.menu_book;
      default:
        return Icons.folder_special;
    }
  }

  @override
  Widget build(BuildContext context) {
    final domainColor = AppConstants.domainColors[domain.name] ?? AppTheme.primaryColor;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: domainColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_getDomainIcon(domain.name), color: domainColor, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      domain.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${domain.documentCount} document${domain.documentCount > 1 ? 's' : ''}',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              if (domain.isCustom)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'IA',
                    style: TextStyle(fontSize: 10, color: Colors.purple.shade700, fontWeight: FontWeight.bold),
                  ),
                ),
              const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
