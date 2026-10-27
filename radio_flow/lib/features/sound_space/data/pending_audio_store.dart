import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
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

/// Web : pas de disque. Les sons en attente restent en mémoire tant que l'onglet est ouvert.
class MemoryPendingAudioStore implements PendingAudioStore {
  final _files = <String, Uint8List>{};
  int _next = 1;

  @override
  Future<String> save(Uint8List bytes) async {
    final ref = 'mem-${_next++}';
    _files[ref] = bytes;
    return ref;
  }

  @override
  Future<Uint8List> read(String ref) async {
    final bytes = _files[ref];
    if (bytes == null) throw StateError('Fichier en attente introuvable');
    return bytes;
  }

  @override
  Future<void> delete(String ref) async => _files.remove(ref);
}

final pendingAudioStoreProvider = Provider<PendingAudioStore>(
  (ref) => kIsWeb ? MemoryPendingAudioStore() : DiskPendingAudioStore(),
);
