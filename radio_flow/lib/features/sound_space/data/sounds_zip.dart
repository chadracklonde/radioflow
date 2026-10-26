import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../domain/sound_file.dart';
import 'sound_repository.dart';

/// Assemble des fichiers (nom -> contenu) en une archive zip.
/// Les sons sont déjà compressés : on les stocke sans recompression.
Uint8List buildZip(Map<String, Uint8List> files) {
  final archive = Archive();
  files.forEach((name, bytes) {
    archive.addFile(ArchiveFile.noCompress(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

/// Télécharge tous les sons donnés et les range dans un zip (noms automatiques conservés).
Future<Uint8List> zipSounds(
  SoundRepository repo,
  List<SoundFile> files, {
  void Function(int done, int total)? onProgress,
}) async {
  final out = <String, Uint8List>{};
  for (var i = 0; i < files.length; i++) {
    out[files[i].storedName] = await repo.download(files[i].storagePath);
    onProgress?.call(i + 1, files.length);
  }
  return buildZip(out);
}
