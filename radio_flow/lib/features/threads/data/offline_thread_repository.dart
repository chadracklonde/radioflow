import 'package:uuid/uuid.dart';

import '../../../core/network/network_errors.dart';
import '../../../data/local/local_store.dart';
import '../../../data/sync/offline_stream.dart';
import '../../../data/sync/sync_service.dart';
import '../domain/thread_message.dart';
import 'thread_repository.dart';

/// Fils de discussion utilisables sans réseau : lecture de la dernière version, messages mis en file.
/// L'envoi de fichiers audio reste en ligne uniquement.
class OfflineThreadRepository implements ThreadRepository {
  OfflineThreadRepository({
    required this.remote,
    required this.store,
    required this.sync,
  });

  static const sendKind = 'thread.sendText';

  final ThreadRepository remote;
  final LocalStore store;
  final SyncService sync;

  @override
  Future<String> threadIdForLine(String lineId) async {
    final key = 'thread:$lineId';
    try {
      final id = await remote.threadIdForLine(lineId);
      await store.writeCache(key, [
        {'id': id},
      ]);
      return id;
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      final cached = await store.readCache(key);
      if (cached != null && cached.isNotEmpty) {
        return (cached.first as Map)['id'] as String;
      }
      rethrow;
    }
  }

  @override
  Future<String> threadIdForProposal(String proposalId) async {
    final key = 'thread:proposal:$proposalId';
    try {
      final id = await remote.threadIdForProposal(proposalId);
      await store.writeCache(key, [
        {'id': id},
      ]);
      return id;
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      final cached = await store.readCache(key);
      if (cached != null && cached.isNotEmpty) {
        return (cached.first as Map)['id'] as String;
      }
      rethrow;
    }
  }

  @override
  Stream<List<ThreadMessage>> watchMessages(String threadId) =>
      offlineFirst<ThreadMessage>(
        store: store,
        key: 'messages:$threadId',
        remote: () => remote.watchMessages(threadId),
        toJson: (m) => m.toJson(),
        fromJson: ThreadMessage.fromJson,
        overlay: (base, outbox) => overlay(threadId, base, outbox),
        reconnect: sync.reconnect,
      );

  static List<ThreadMessage> overlay(
    String threadId,
    List<ThreadMessage> base,
    List<OutboxItem> outbox,
  ) {
    final known = {for (final m in base) m.id};
    final pending = [
      for (final op in outbox)
        if (op.kind == sendKind &&
            !op.failed &&
            op.payload['thread_id'] == threadId &&
            !known.contains(op.payload['id']))
          ThreadMessage(
            id: op.payload['id'] as String,
            userId: op.payload['user_id'] as String,
            createdAt: DateTime.parse(op.payload['created_at'] as String),
            content: op.payload['text'] as String,
            pendingSync: true,
          ),
    ];
    return [...base, ...pending];
  }

  @override
  Future<void> sendText({
    String? id,
    required String threadId,
    required String userId,
    required String text,
  }) async {
    final payload = {
      'id': id ?? const Uuid().v4(),
      'thread_id': threadId,
      'user_id': userId,
      'text': text.trim(),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (await store.hasPending()) {
      await store.enqueue(sendKind, payload);
      return;
    }
    try {
      await sendOp(remote, payload);
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      await store.enqueue(sendKind, payload);
    }
  }

  static Future<void> sendOp(ThreadRepository remote, Map<String, dynamic> p) =>
      remote.sendText(
        id: p['id'] as String,
        threadId: p['thread_id'] as String,
        userId: p['user_id'] as String,
        text: p['text'] as String,
      );
}
