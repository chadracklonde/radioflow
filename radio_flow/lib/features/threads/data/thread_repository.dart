import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/local/local_store.dart';
import '../../../data/sync/sync_providers.dart';
import '../domain/thread_message.dart';
import 'offline_thread_repository.dart';

abstract class ThreadRepository {
  /// Identifiant du fil de la ligne (créé automatiquement par la base).
  Future<String> threadIdForLine(String lineId);

  /// Identifiant du fil d'un sujet validé (créé par la base à la validation).
  Future<String> threadIdForProposal(String proposalId);
  Stream<List<ThreadMessage>> watchMessages(String threadId);
  Future<void> sendText({
    String? id,
    required String threadId,
    required String userId,
    required String text,
  });
}

class SupabaseThreadRepository implements ThreadRepository {
  SupabaseThreadRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<String> threadIdForLine(String lineId) async {
    final row = await _client
        .from('discussion_threads')
        .select('id')
        .eq('conductor_line_id', lineId)
        .single();
    return row['id'] as String;
  }

  @override
  Future<String> threadIdForProposal(String proposalId) async {
    final row = await _client
        .from('discussion_threads')
        .select('id')
        .eq('proposal_id', proposalId)
        .single();
    return row['id'] as String;
  }

  @override
  Stream<List<ThreadMessage>> watchMessages(String threadId) => _client
      .from('messages')
      .stream(primaryKey: ['id'])
      .eq('thread_id', threadId)
      .order('created_at')
      .map((rows) => rows.map(ThreadMessage.fromJson).toList());

  @override
  Future<void> sendText({
    String? id,
    required String threadId,
    required String userId,
    required String text,
  }) async {
    await _client.from('messages').insert({
      'id': ?id,
      'thread_id': threadId,
      'user_id': userId,
      'content': text.trim(),
    });
  }
}

final threadRemoteProvider = Provider<ThreadRepository>(
  (ref) => SupabaseThreadRepository(Supabase.instance.client),
);

final threadRepositoryProvider = Provider<ThreadRepository>(
  (ref) => OfflineThreadRepository(
    remote: ref.watch(threadRemoteProvider),
    store: ref.watch(localStoreProvider),
    sync: ref.watch(syncServiceProvider),
  ),
);

final threadIdProvider = FutureProvider.autoDispose.family<String, String>(
  (ref, lineId) => ref.watch(threadRepositoryProvider).threadIdForLine(lineId),
);

final proposalThreadIdProvider = FutureProvider.autoDispose
    .family<String, String>(
      (ref, proposalId) =>
          ref.watch(threadRepositoryProvider).threadIdForProposal(proposalId),
    );

final messagesProvider = StreamProvider.autoDispose
    .family<List<ThreadMessage>, String>(
      (ref, threadId) =>
          ref.watch(threadRepositoryProvider).watchMessages(threadId),
    );
