import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  final double size;
  final bool showText;
  final bool isDark;

  const AppLogo({
    super.key,
    this.size = 48,
    this.showText = false,
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconWidget = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF2563EB), Color(0xFF0D9488)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.26),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E3A8A).withOpacity(0.35),
            blurRadius: size * 0.25,
            offset: Offset(0, size * 0.1),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Livre ouvert
          Icon(
            Icons.menu_book_rounded,
            color: Colors.white,
            size: size * 0.55,
          ),
          // Étoile / étincelle IA
          Positioned(
            top: size * 0.16,
            right: size * 0.16,
            child: Container(
              padding: EdgeInsets.all(size * 0.04),
              decoration: const BoxDecoration(
                color: Color(0xFFFBBF24),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_awesome,
                color: const Color(0xFF78350F),
                size: size * 0.22,
              ),
            ),
          ),
        ],
      ),
    );

    if (!showText) return iconWidget;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        iconWidget,
        const SizedBox(width: 12),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bibliothèque PDF',
              style: TextStyle(
                fontSize: size * 0.42,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                letterSpacing: -0.5,
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D9488).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'INTELLIGENTE',
                    style: TextStyle(
                      fontSize: size * 0.20,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0D9488),
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Multi-IA',
                  style: TextStyle(
                    fontSize: size * 0.20,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
