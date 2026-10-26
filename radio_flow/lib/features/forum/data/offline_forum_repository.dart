import 'package:uuid/uuid.dart';

import '../../../core/network/network_errors.dart';
import '../../../data/local/local_store.dart';
import '../../../data/sync/offline_stream.dart';
import '../../../data/sync/sync_service.dart';
import '../domain/forum_proposal.dart';
import 'forum_repository.dart';

/// Forum utilisable sans réseau : lecture de la dernière version, propositions mises en file.
/// Les décisions du rédacteur en chef restent en ligne uniquement.
class OfflineForumRepository implements ForumRepository {
  OfflineForumRepository({
    required this.remote,
    required this.store,
    required this.sync,
  });

  static const proposeKind = 'forum.propose';

  final ForumRepository remote;
  final LocalStore store;
  final SyncService sync;

  @override
  Stream<List<ForumProposal>> watch() => offlineFirst<ForumProposal>(
    store: store,
    key: 'forum',
    remote: remote.watch,
    toJson: (p) => p.toJson(),
    fromJson: ForumProposal.fromJson,
    overlay: overlay,
    reconnect: sync.reconnect,
  );

  static List<ForumProposal> overlay(
    List<ForumProposal> base,
    List<OutboxItem> outbox,
  ) {
    final known = {for (final p in base) p.id};
    final pending = [
      for (final op in outbox)
        if (op.kind == proposeKind &&
            !op.failed &&
            !known.contains(op.payload['id']))
          ForumProposal(
            id: op.payload['id'] as String,
            authorId: op.payload['author_id'] as String,
            title: op.payload['title'] as String,
            angle: op.payload['angle'] as String,
            format: ProposalFormat.values.byName(
              op.payload['format'] as String,
            ),
            status: ProposalStatus.pending,
            createdAt: DateTime.parse(op.payload['created_at'] as String),
            source: op.payload['source'] as String?,
            pendingSync: true,
          ),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return [...pending, ...base];
  }

  @override
  Future<void> propose({
    String? id,
    required String authorId,
    required String title,
    required String angle,
    required ProposalFormat format,
    String? source,
  }) async {
    final payload = {
      'id': id ?? const Uuid().v4(),
      'author_id': authorId,
      'title': title.trim(),
      'angle': angle.trim(),
      'format': format.name,
      if (source != null && source.trim().isNotEmpty) 'source': source.trim(),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    // Si des opérations attendent déjà, on s'ajoute à la file pour garder l'ordre.
    if (await store.hasPending()) {
      await store.enqueue(proposeKind, payload);
      return;
    }
    try {
      await sendPropose(remote, payload);
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      await store.enqueue(proposeKind, payload);
    }
  }

  static Future<void> sendPropose(
    ForumRepository remote,
    Map<String, dynamic> p,
  ) => remote.propose(
    id: p['id'] as String,
    authorId: p['author_id'] as String,
    title: p['title'] as String,
    angle: p['angle'] as String,
    format: ProposalFormat.values.byName(p['format'] as String),
    source: p['source'] as String?,
  );

  /// Le placement au conducteur exige le réseau (comme les décisions du forum).
  @override
  Future<void> linkToLine(String proposalId, String lineId) =>
      remote.linkToLine(proposalId, lineId);

  @override
  Future<void> decide(String id, ProposalStatus status, {String? note}) =>
      remote.decide(id, status, note: note);
}
