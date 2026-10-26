import 'dart:typed_data';

import '../../../core/network/network_errors.dart';
import '../../../core/utils/audio_naming.dart';
import '../../../data/local/local_store.dart';
import '../../../data/sync/sync_service.dart';
import '../domain/sound_file.dart';
import 'pending_audio_store.dart';
import 'sound_repository.dart';

/// Espace Son utilisable sans réseau : liste de la dernière version consultée, et envoi de sons
/// conservé sur l'appareil puis transmis au retour du réseau. Lecture, téléchargement et
/// suppression restent en ligne.
class OfflineSoundRepository implements SoundRepository {
  OfflineSoundRepository({
    required this.remote,
    required this.store,
    required this.sync,
    required this.files,
  });

  static const uploadKind = 'sound.upload';

  final SoundRepository remote;
  final LocalStore store;
  final SyncService sync;
  final PendingAudioStore files;

  @override
  Future<List<SoundFile>> fetchFiles(String isoDate) async {
    final key = 'sounds:$isoDate';
    try {
      final list = await remote.fetchFiles(isoDate);
      await store.writeCache(key, [for (final f in list) f.toJson()]);
      return list;
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      final cached = await store.readCache(key);
      if (cached == null) rethrow;
      return [
        for (final r in cached)
          SoundFile.fromJson(Map<String, dynamic>.from(r as Map)),
      ];
    }
  }

  @override
  Stream<void> changes() => remote.changes();

  @override
  Future<String> upload({
    required String conductorId,
    required String threadId,
    required String userId,
    required int position,
    required DateTime date,
    required String originalName,
    required Uint8List bytes,
    int? durationSeconds,
  }) async {
    Future<String> send() => remote.upload(
      conductorId: conductorId,
      threadId: threadId,
      userId: userId,
      position: position,
      date: date,
      originalName: originalName,
      bytes: bytes,
      durationSeconds: durationSeconds,
    );

    Future<String> queue() async {
      final ref = await files.save(bytes);
      await store.enqueue(uploadKind, {
        'conductor_id': conductorId,
        'thread_id': threadId,
        'user_id': userId,
        'position': position,
        'date': date.toIso8601String(),
        'original_name': originalName,
        'duration': durationSeconds,
        'file': ref,
      });
      return audioStoredName(
        position: position,
        originalName: originalName,
        date: date,
      );
    }

    // Une opération en attente passe d'abord : l'ordre est conservé.
    if (await store.hasPending()) return queue();
    try {
      return await send();
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      return queue();
    }
  }

  /// Envoi d'un son mis en file; le fichier local est supprimé une fois transmis.
  static Future<void> sendUpload(
    SoundRepository remote,
    PendingAudioStore files,
    Map<String, dynamic> p,
  ) async {
    final bytes = await files.read(p['file'] as String);
    try {
      await remote.upload(
        conductorId: p['conductor_id'] as String,
        threadId: p['thread_id'] as String,
        userId: p['user_id'] as String,
        position: p['position'] as int,
        date: DateTime.parse(p['date'] as String),
        originalName: p['original_name'] as String,
        bytes: bytes,
        durationSeconds: p['duration'] as int?,
      );
    } on DuplicateAudioException catch (e) {
      throw StateError(
        'Un fichier ${e.name} existe déjà dans cette édition : renvoyez-le sous un autre nom.',
      );
    }
    await files.delete(p['file'] as String);
  }

  @override
  Future<void> deleteSound(SoundFile file) => remote.deleteSound(file);
  @override
  Future<String> signedUrl(String path) => remote.signedUrl(path);
  @override
  Future<Uint8List> download(String path) => remote.download(path);
}
