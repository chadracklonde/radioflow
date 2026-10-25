import 'package:uuid/uuid.dart';

import '../../../core/network/network_errors.dart';
import '../../../data/local/local_store.dart';
import '../../../data/sync/offline_stream.dart';
import '../../../data/sync/sync_service.dart';
import '../domain/task_models.dart';
import 'tasks_repository.dart';

/// Tâches utilisables sans réseau : création, changement de statut et suppression sont mis en file.
class OfflineTasksRepository implements TasksRepository {
  OfflineTasksRepository({
    required this.remote,
    required this.store,
    required this.sync,
  });

  static const addKind = 'task.add';
  static const statusKind = 'task.setStatus';
  static const deleteKind = 'task.delete';

  final TasksRepository remote;
  final LocalStore store;
  final SyncService sync;

  @override
  Stream<List<TeamTask>> watch() => offlineFirst<TeamTask>(
    store: store,
    key: 'tasks',
    remote: remote.watch,
    toJson: (t) => t.toJson(),
    fromJson: TeamTask.fromJson,
    overlay: overlay,
    reconnect: sync.reconnect,
  );

  /// Rejoue les opérations en attente, dans l'ordre, sur la dernière liste connue.
  static List<TeamTask> overlay(List<TeamTask> base, List<OutboxItem> outbox) {
    final list = List.of(base);
    for (final op in outbox) {
      if (op.failed) continue;
      final id = op.payload['id'] as String;
      final index = list.indexWhere((t) => t.id == id);
      switch (op.kind) {
        case addKind:
          if (index < 0) {
            list.insert(
              0,
              TeamTask(
                id: id,
                userId: op.payload['user_id'] as String,
                title: op.payload['title'] as String,
                status: TaskStatus.todo,
                dueDate: op.payload['due_date'] == null
                    ? null
                    : DateTime.parse(op.payload['due_date'] as String),
                pendingSync: true,
              ),
            );
          }
        case statusKind:
          if (index >= 0) {
            list[index] = list[index].copyWith(
              status: TaskStatus.parse(op.payload['status'] as String),
              pendingSync: true,
            );
          }
        case deleteKind:
          if (index >= 0) list.removeAt(index);
      }
    }
    return list;
  }

  Future<void> _run(
    String kind,
    Map<String, dynamic> payload,
    Future<void> Function() send,
  ) async {
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
  Future<void> add({
    String? id,
    required String userId,
    required String title,
    DateTime? dueDate,
  }) {
    final payload = {
      'id': id ?? const Uuid().v4(),
      'user_id': userId,
      'title': title.trim(),
      if (dueDate != null)
        'due_date': dueDate.toIso8601String().substring(0, 10),
    };
    return _run(addKind, payload, () => sendAdd(remote, payload));
  }

  static Future<void> sendAdd(TasksRepository remote, Map<String, dynamic> p) =>
      remote.add(
        id: p['id'] as String,
        userId: p['user_id'] as String,
        title: p['title'] as String,
        dueDate: p['due_date'] == null
            ? null
            : DateTime.parse(p['due_date'] as String),
      );

  @override
  Future<void> setStatus(String id, TaskStatus status) => _run(statusKind, {
    'id': id,
    'status': status.name,
  }, () => remote.setStatus(id, status));

  @override
  Future<void> delete(String id) =>
      _run(deleteKind, {'id': id}, () => remote.delete(id));
}
