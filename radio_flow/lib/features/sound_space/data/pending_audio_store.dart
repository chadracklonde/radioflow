import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Conserve sur l'appareil les fichiers audio en attente d'envoi (mode hors ligne).
abstract class PendingAudioStore {
  /// Enregistre le fichier et renvoie sa référence.
  Future<String> save(Uint8List bytes);
  Future<Uint8List> read(String ref);
  Future<void> delete(String ref);
}

class DiskPendingAudioStore implements PendingAudioStore {
  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'pending_audio'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  @override
  Future<String> save(Uint8List bytes) async {
    final ref = '${const Uuid().v4()}.bin';
    final file = File(p.join((await _dir()).path, ref));
    await file.writeAsBytes(bytes, flush: true);
    return ref;
  }

  @override
  Future<Uint8List> read(String ref) async =>
      File(p.join((await _dir()).path, p.basename(ref))).readAsBytes();

  @override
  Future<void> delete(String ref) async {
    final file = File(p.join((await _dir()).path, p.basename(ref)));
    if (await file.exists()) await file.delete();
  }
}

final pendingAudioStoreProvider = Provider<PendingAudioStore>(
  (ref) => DiskPendingAudioStore(),
);
