import 'dart:io';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/text_sanitizer.dart';

class PdfExtractionResult {
  final String text;
  final int pageCount;
  final bool isEncrypted;
  final bool isScanOnly;

  PdfExtractionResult({
    required this.text,
    required this.pageCount,
    this.isEncrypted = false,
    this.isScanOnly = false,
  });
}

class PdfExtractorService {
  static final PdfExtractorService instance = PdfExtractorService._init();
  PdfExtractorService._init();

  /// Extrait le texte des $pageLimit premières pages d'un fichier PDF
  Future<PdfExtractionResult> extractText(
    File file, {
    int pageLimit = AppConstants.defaultScanPageCount,
  }) async {
    try {
      final bytes = await file.readAsBytes();
      final PdfDocument document = PdfDocument(inputBytes: bytes);

      final totalPages = document.pages.count;
      final pagesToExtract = totalPages < pageLimit ? totalPages : pageLimit;

      final StringBuffer buffer = StringBuffer();
      final PdfTextExtractor extractor = PdfTextExtractor(document);

      for (int i = 0; i < pagesToExtract; i++) {
        // Dans Syncfusion, les pages sont 0-indexed dans l'extracteur
        final pageText = extractor.extractText(startPageIndex: i, endPageIndex: i);
        if (pageText.trim().isNotEmpty) {
          buffer.writeln('--- Page ${i + 1} ---');
          buffer.writeln(pageText);
        }
      }

      document.dispose();

      final rawExtracted = buffer.toString();
      final cleanText = TextSanitizer.sanitizeForAi(rawExtracted);

      final isScanOnly = cleanText.trim().isEmpty && totalPages > 0;

      return PdfExtractionResult(
        text: cleanText,
        pageCount: totalPages,
        isScanOnly: isScanOnly,
      );
    } catch (e) {
      // Si le PDF est chiffré par mot de passe ou corrompu
      final errorStr = e.toString().toLowerCase();
      final isEncrypted = errorStr.contains('password') || errorStr.contains('encrypted');
      return PdfExtractionResult(
        text: '',
        pageCount: 0,
        isEncrypted: isEncrypted,
      );
    }
  }
}
