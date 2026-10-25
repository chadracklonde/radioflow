import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/local/local_store.dart';
import '../../../data/sync/sync_providers.dart';
import '../domain/task_models.dart';
import 'offline_tasks_repository.dart';

abstract class TasksRepository {
  /// Toutes les tâches de l'équipe, en temps réel.
  Stream<List<TeamTask>> watch();
  Future<void> add({
    String? id,
    required String userId,
    required String title,
    DateTime? dueDate,
  });
  Future<void> setStatus(String id, TaskStatus status);
  Future<void> delete(String id);
}

class SupabaseTasksRepository implements TasksRepository {
  SupabaseTasksRepository(this._client);
  final SupabaseClient _client;

  @override
  Stream<List<TeamTask>> watch() => _client
      .from('tasks')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .map((rows) => rows.map(TeamTask.fromJson).toList());

  @override
  Future<void> add({
    String? id,
    required String userId,
    required String title,
    DateTime? dueDate,
  }) async {
    await _client.from('tasks').insert({
      'id': ?id,
      'user_id': userId,
      'title': title.trim(),
      if (dueDate != null) 'due_date': DateFormat('yyyy-MM-dd').format(dueDate),
    });
  }

  @override
  Future<void> setStatus(String id, TaskStatus status) async {
    await _client.from('tasks').update({'status': status.name}).eq('id', id);
  }

  @override
  Future<void> delete(String id) async {
    await _client.from('tasks').delete().eq('id', id);
  }
}

final tasksRemoteProvider = Provider<TasksRepository>(
  (ref) => SupabaseTasksRepository(Supabase.instance.client),
);

final tasksRepositoryProvider = Provider<TasksRepository>(
  (ref) => OfflineTasksRepository(
    remote: ref.watch(tasksRemoteProvider),
    store: ref.watch(localStoreProvider),
    sync: ref.watch(syncServiceProvider),
  ),
);

final tasksProvider = StreamProvider<List<TeamTask>>(
  (ref) => ref.watch(tasksRepositoryProvider).watch(),
);

extension TaskStatusParse on TaskStatus {
  static TaskStatus fromName(String name) => TaskStatus.parse(name);
}
