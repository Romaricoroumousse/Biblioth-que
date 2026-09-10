import 'dart:io';
import 'package:crypto/crypto.dart';

class FileHash {
  /// Calcule l'empreinte SHA-256 d'un fichier.
  /// Pour optimiser les performances sur mobile sur de très gros fichiers (> 30 Mo),
  /// combine les premiers mégaoctets, la taille et la date de modification.
  static Future<String> calculate(File file) async {
    try {
      final length = await file.length();
      // Si le fichier fait moins de 20 Mo, hacher l'intégralité
      if (length <= 20 * 1024 * 1024) {
        final stream = file.openRead();
        final digest = await sha256.bind(stream).first;
        return digest.toString();
      }

      // Pour les très gros fichiers, hacher les premiers 2 Mo + taille
      final randomAccess = await file.open(mode: FileMode.read);
      try {
        final buffer = List<int>.filled(2 * 1024 * 1024, 0);
        final bytesRead = await randomAccess.readInto(buffer);
        final slice = buffer.sublist(0, bytesRead);
        // Ajouter la taille en octets dans l'empreinte
        slice.addAll(length.toString().codeUnits);
        final digest = sha256.convert(slice);
        return digest.toString();
      } finally {
        await randomAccess.close();
      }
    } catch (e) {
      // En cas d'erreur de lecture, générer un hash basé sur le chemin et la date
      final stat = await file.stat();
      final fallbackString = '${file.path}_${stat.size}_${stat.modified.millisecondsSinceEpoch}';
      return sha256.convert(fallbackString.codeUnits).toString();
    }
  }
}
