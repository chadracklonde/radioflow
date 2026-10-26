import 'package:uuid/uuid.dart';

import '../../../core/network/network_errors.dart';
import '../../../data/local/local_store.dart';
import '../../../data/sync/offline_stream.dart';
import '../../../data/sync/sync_service.dart';
import '../domain/conductor_models.dart';
import 'conductor_repository.dart';

/// Conducteurs utilisables sans réseau : lecture de la dernière version consultée, et
/// ajout de ligne, statut de ligne et texte à l'antenne mis en file d'envoi.
/// Restent en ligne : génération, grille, réordonnancement, statut du conducteur, modèles.
class OfflineConductorRepository implements ConductorRepository {
  OfflineConductorRepository({
    required this.remote,
    required this.store,
    required this.sync,
  });

  static const addLineKind = 'line.add';
  static const lineStatusKind = 'line.setStatus';
  static const lineScriptKind = 'line.setScript';

  final ConductorRepository remote;
  final LocalStore store;
  final SyncService sync;

  @override
  Stream<List<Conductor>> watchConductors(String isoDate) =>
      offlineFirst<Conductor>(
        store: store,
        key: 'conductors:$isoDate',
        remote: () => remote.watchConductors(isoDate),
        toJson: (c) => c.toJson(),
        fromJson: Conductor.fromJson,
        overlay: (base, _) => base,
        reconnect: sync.reconnect,
      );

  @override
  Stream<List<ConductorLine>> watchLines(String conductorId) =>
      offlineFirst<ConductorLine>(
        store: store,
        key: 'lines:$conductorId',
        remote: () => remote.watchLines(conductorId),
        toJson: (l) => l.toJson(),
        fromJson: ConductorLine.fromJson,
        overlay: (base, outbox) => overlay(conductorId, base, outbox),
        reconnect: sync.reconnect,
      );

  /// Rejoue les opérations en attente, dans l'ordre, sur la dernière liste connue.
  static List<ConductorLine> overlay(
    String conductorId,
    List<ConductorLine> base,
    List<OutboxItem> outbox,
  ) {
    final list = List.of(base);
    for (final op in outbox) {
      if (op.failed) continue;
      switch (op.kind) {
        case addLineKind:
          if (op.payload['conductor_id'] != conductorId) continue;
          final id = op.payload['id'] as String;
          if (list.any((l) => l.id == id)) continue;
          final last = list.fold<int>(
            0,
            (m, l) => l.position > m ? l.position : m,
          );
          list.add(
            ConductorLine(
              id: id,
              conductorId: conductorId,
              position: last + 1,
              itemType: LineItemType.parse(op.payload['item_type'] as String),
              title: op.payload['title'] as String,
              status: LineStatus.planned,
              plannedDuration: op.payload['planned_duration'] as int?,
              pendingSync: true,
            ),
          );
        case lineStatusKind:
          final i = list.indexWhere((l) => l.id == op.payload['id']);
          if (i >= 0) {
            list[i] = list[i].copyWith(
              status: LineStatus.parse(op.payload['status'] as String),
              pendingSync: true,
            );
          }
        case lineScriptKind:
          final i = list.indexWhere((l) => l.id == op.payload['id']);
          if (i >= 0) {
            final text = op.payload['text'] as String?;
            list[i] = list[i].copyWith(
              script: text,
              clearScript: text == null || text.isEmpty,
              pendingSync: true,
            );
          }
      }
    }
    return list;
  }

  @override
  Future<List<BroadcastSlot>> fetchSlots() async {
    const key = 'slots';
    try {
      final slots = await remote.fetchSlots();
      await store.writeCache(key, [for (final s in slots) s.toJson()]);
      return slots;
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      final cached = await store.readCache(key);
      if (cached == null) rethrow;
      return [
        for (final r in cached)
          BroadcastSlot.fromJson(Map<String, dynamic>.from(r as Map)),
      ];
    }
  }

  Future<void> _run(
    String kind,
    Map<String, dynamic> payload,
    Future<void> Function() send,
  ) async {
    // Une opération en attente passe d'abord : l'ordre de rédaction est conservé.
    if (await store.hasPending()) {
      await store.enqueue(kind, payload);
      return;
    }
    try {
      await send();
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      await store.enqueue(kind, payload);
    }
  }

  @override
  Future<String> addLine({
    String? id,
    required String conductorId,
    required String title,
    required LineItemType type,
    int? plannedDuration,
  }) async {
    final lineId = id ?? const Uuid().v4();
    final payload = {
      'id': lineId,
      'conductor_id': conductorId,
      'title': title.trim(),
      'item_type': type.name,
      'planned_duration': plannedDuration,
    };
    await _run(addLineKind, payload, () => sendAddLine(remote, payload));
    return lineId;
  }

  static Future<void> sendAddLine(
    ConductorRepository remote,
    Map<String, dynamic> p,
  ) async {
    await remote.addLine(
      id: p['id'] as String,
      conductorId: p['conductor_id'] as String,
      title: p['title'] as String,
      type: LineItemType.parse(p['item_type'] as String),
      plannedDuration: p['planned_duration'] as int?,
    );
  }

  @override
  Future<void> setLineStatus(String id, LineStatus status) {
    final payload = {'id': id, 'status': status.dbValue};
    return _run(
      lineStatusKind,
      payload,
      () => remote.setLineStatus(id, status),
    );
  }

  @override
  Future<void> setLineScript(String lineId, String? text) {
    final payload = {'id': lineId, 'text': text};
    return _run(
      lineScriptKind,
      payload,
      () => remote.setLineScript(lineId, text),
    );
  }

  // --- en ligne uniquement ---

  @override
  Future<int> generate(DateTime date) => remote.generate(date);
  @override
  Future<void> addSlot({
    required String title,
    required String time,
    List<int> weekdays = BroadcastSlot.allWeekdays,
    int? durationSeconds,
  }) => remote.addSlot(
    title: title,
    time: time,
    weekdays: weekdays,
    durationSeconds: durationSeconds,
  );
  @override
  Future<void> removeSlot(String id) => remote.removeSlot(id);
  @override
  Future<int> saveAsTemplate(String conductorId) =>
      remote.saveAsTemplate(conductorId);
  @override
  Future<List<HistoryEntry>> fetchHistory(String conductorId) =>
      remote.fetchHistory(conductorId);
  @override
  Future<void> swapLines(String a, String b) => remote.swapLines(a, b);
  @override
  Future<void> setConductorStatus(String id, ConductorStatus status) =>
      remote.setConductorStatus(id, status);
}
