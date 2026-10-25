import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Enregistrement d'un fichier généré (export PDF / Excel), isolé pour les tests.
abstract class FileSaver {
  /// Renvoie false si l'utilisateur annule.
  Future<bool> save({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  });
}

class FilePickerFileSaver implements FileSaver {
  @override
  Future<bool> save({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeType,
    );
    return uri != null;
  }
}

final fileSaverProvider = Provider<FileSaver>((ref) => FilePickerFileSaver());
