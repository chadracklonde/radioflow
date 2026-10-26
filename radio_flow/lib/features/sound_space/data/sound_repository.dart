import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/audio_naming.dart';
import '../../../data/local/local_store.dart';
import '../../../data/sync/sync_providers.dart';
import '../domain/sound_file.dart';
import 'offline_sound_repository.dart';
import 'pending_audio_store.dart';
import 'audio_services.dart';

/// Un fichier de ce nom existe déjà dans l'édition.
class DuplicateAudioException implements Exception {
  const DuplicateAudioException(this.name);
  final String name;

  @override
  String toString() => 'Un fichier $name existe déjà dans cette édition.';
}

abstract class SoundRepository {
  Future<List<SoundFile>> fetchFiles(String isoDate);

  /// Émet à chaque changement de messages (pour rafraîchir la liste).
  Stream<void> changes();

  /// Envoie le fichier sous son nom automatique et publie le message dans le fil.
  /// Renvoie le nom renommé.
  Future<String> upload({
    required String conductorId,
    required String threadId,
    required String userId,
    required int position,
    required DateTime date,
    required String originalName,
    required Uint8List bytes,
    int? durationSeconds,
  });

  /// Supprime le message audio puis le fichier.
  Future<void> deleteSound(SoundFile file);

  Future<String> signedUrl(String path);
  Future<Uint8List> download(String path);
}

class SupabaseSoundRepository implements SoundRepository {
  SupabaseSoundRepository(this._client);
  final SupabaseClient _client;

  static const _bucket = 'conductor-audio';

  @override
  Future<List<SoundFile>> fetchFiles(String isoDate) async {
    final rows = await _client
        .from('sound_files')
        .select()
        .eq('broadcast_date', isoDate)
        .order('broadcast_time')
        .order('position_index')
        .order('uploaded_at');
    return rows.map(SoundFile.fromJson).toList();
  }

  @override
  Stream<void> changes() {
    final controller = StreamController<void>();
    final channel = _client
        .channel('sound-files-${DateTime.now().microsecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (_) => controller.add(null),
        )
        .subscribe();
    controller.onCancel = () => _client.removeChannel(channel);
    return controller.stream;
  }

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
    final stored = audioStoredName(
      position: position,
      originalName: originalName,
      date: date,
    );
    final path = '$conductorId/$stored';
    try {
      await _client.storage
          .from(_bucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: lookupMimeType(stored) ?? 'application/octet-stream',
              upsert: false,
            ),
          );
    } on StorageException catch (e) {
      if (e.statusCode == '409' ||
          e.message.toLowerCase().contains('already exists')) {
        throw DuplicateAudioException(stored);
      }
      rethrow;
    }
    try {
      await _client.from('messages').insert({
        'thread_id': threadId,
        'user_id': userId,
        'audio_file_url': path,
        'audio_original_name': originalName,
        'audio_duration': durationSeconds,
      });
    } catch (_) {
      // Pas de fichier orphelin si le message n'a pas pu être publié.
      await _client.storage.from(_bucket).remove([path]);
      rethrow;
    }
    return stored;
  }

  @override
  Future<void> deleteSound(SoundFile file) async {
    // Le message d'abord : sans lui, plus personne ne voit le fichier.
    final deleted = await _client
        .from('messages')
        .delete()
        .eq('id', file.messageId)
        .select('id');
    if (deleted.isEmpty) throw StateError('Suppression refusée');
    await _client.storage.from(_bucket).remove([file.storagePath]);
  }

  @override
  Future<String> signedUrl(String path) =>
      _client.storage.from(_bucket).createSignedUrl(path, 3600);

  @override
  Future<Uint8List> download(String path) =>
      _client.storage.from(_bucket).download(path);
}

final soundRemoteProvider = Provider<SoundRepository>(
  (ref) => SupabaseSoundRepository(Supabase.instance.client),
);

final soundRepositoryProvider = Provider<SoundRepository>(
  (ref) => OfflineSoundRepository(
    remote: ref.watch(soundRemoteProvider),
    store: ref.watch(localStoreProvider),
    sync: ref.watch(syncServiceProvider),
    files: ref.watch(pendingAudioStoreProvider),
  ),
);

final soundFilesProvider = FutureProvider.autoDispose
    .family<List<SoundFile>, String>((ref, isoDate) {
      final repo = ref.watch(soundRepositoryProvider);
      final sub = repo.changes().listen((_) => ref.invalidateSelf());
      ref.onDispose(sub.cancel);
      return repo.fetchFiles(isoDate);
    });

/// Chemin du fichier en cours de lecture (null si aucun).
class NowPlaying extends Notifier<String?> {
  StreamSubscription<void>? _sub;

  @override
  String? build() => null;

  Future<void> toggle(
    String path,
    AudioPlayerService player,
    SoundRepository repo,
  ) async {
    if (state == path) {
      await player.stop();
      state = null;
      return;
    }
    await _sub?.cancel();
    state = path;
    try {
      final url = await repo.signedUrl(path);
      await player.play(url);
      _sub = player.completed.listen((_) => state = null);
    } catch (_) {
      state = null;
      rethrow;
    }
  }
}

final nowPlayingProvider = NotifierProvider<NowPlaying, String?>(
  NowPlaying.new,
);
