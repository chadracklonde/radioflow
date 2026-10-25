import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/forum/data/forum_repository.dart';
import '../../features/forum/data/offline_forum_repository.dart';
import '../../features/tasks/data/offline_tasks_repository.dart';
import '../../features/tasks/data/tasks_repository.dart';
import '../../features/threads/data/offline_thread_repository.dart';
import '../../features/threads/data/thread_repository.dart';
import '../local/local_store.dart';
import 'connectivity_service.dart';
import 'sync_service.dart';

/// Service de synchronisation de l'application. Les dépôts distants sont résolus
/// au moment de l'envoi, pas à la création, pour ne rien exiger au démarrage.
final syncServiceProvider = Provider<SyncService>((ref) {
  final service = SyncService(
    store: ref.watch(localStoreProvider),
    connectivity: ref.watch(connectivityServiceProvider),
    handlers: {
      OfflineForumRepository.proposeKind: (p) =>
          OfflineForumRepository.sendPropose(ref.read(forumRemoteProvider), p),
      OfflineTasksRepository.addKind: (p) =>
          OfflineTasksRepository.sendAdd(ref.read(tasksRemoteProvider), p),
      OfflineTasksRepository.statusKind: (p) => ref
          .read(tasksRemoteProvider)
          .setStatus(
            p['id'] as String,
            TaskStatusParse.fromName(p['status'] as String),
          ),
      OfflineTasksRepository.deleteKind: (p) =>
          ref.read(tasksRemoteProvider).delete(p['id'] as String),
      OfflineThreadRepository.sendKind: (p) =>
          OfflineThreadRepository.sendOp(ref.read(threadRemoteProvider), p),
    },
  );
  service.start();
  ref.onDispose(service.dispose);
  return service;
});

final syncStatusProvider = StreamProvider<SyncStatus>(
  (ref) => ref.watch(syncServiceProvider).status,
);
