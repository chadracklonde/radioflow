import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/local/local_store.dart';
import '../../../data/sync/sync_providers.dart';
import '../domain/forum_proposal.dart';
import 'offline_forum_repository.dart';

abstract class ForumRepository {
  /// Liste en temps réel, plus récentes d'abord.
  Stream<List<ForumProposal>> watch();

  Future<void> propose({
    String? id,
    required String authorId,
    required String title,
    required String angle,
    required ProposalFormat format,
    String? source,
  });

  /// Décision du rédacteur en chef (RLS : réservé à l'admin).
  Future<void> decide(String id, ProposalStatus status, {String? note});

  /// Place un sujet validé sur une ligne du conducteur : son fil de discussion devient celui de la ligne.
  Future<void> linkToLine(String proposalId, String lineId);
}

class SupabaseForumRepository implements ForumRepository {
  SupabaseForumRepository(this._client);
  final SupabaseClient _client;

  @override
  Stream<List<ForumProposal>> watch() => _client
      .from('forum_proposals')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .map((rows) => rows.map(ForumProposal.fromJson).toList());

  @override
  Future<void> propose({
    String? id,
    required String authorId,
    required String title,
    required String angle,
    required ProposalFormat format,
    String? source,
  }) async {
    await _client.from('forum_proposals').insert({
      'id': ?id,
      'author_id': authorId,
      'title': title.trim(),
      'angle': angle.trim(),
      'format': format.name,
      if (source != null && source.trim().isNotEmpty) 'source': source.trim(),
    });
  }

  @override
  Future<void> decide(String id, ProposalStatus status, {String? note}) async {
    await _client
        .from('forum_proposals')
        .update({
          'status': status.dbValue,
          'decision_note': (note == null || note.trim().isEmpty)
              ? null
              : note.trim(),
        })
        .eq('id', id);
  }

  @override
  Future<void> linkToLine(String proposalId, String lineId) async {
    await _client.rpc(
      'link_proposal_to_line',
      params: {'p_proposal_id': proposalId, 'p_line_id': lineId},
    );
  }
}

final forumRemoteProvider = Provider<ForumRepository>(
  (ref) => SupabaseForumRepository(Supabase.instance.client),
);

final forumRepositoryProvider = Provider<ForumRepository>(
  (ref) => OfflineForumRepository(
    remote: ref.watch(forumRemoteProvider),
    store: ref.watch(localStoreProvider),
    sync: ref.watch(syncServiceProvider),
  ),
);

final forumProposalsProvider = StreamProvider<List<ForumProposal>>(
  (ref) => ref.watch(forumRepositoryProvider).watch(),
);
