import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:radio_flow/app.dart';
import 'package:radio_flow/core/network/network_errors.dart';
import 'package:radio_flow/data/local/local_store.dart';
import 'package:radio_flow/data/sync/connectivity_service.dart';
import 'package:radio_flow/data/sync/offline_stream.dart';
import 'package:radio_flow/data/sync/sync_engine.dart';
import 'package:radio_flow/data/sync/sync_service.dart';
import 'package:radio_flow/features/auth/data/auth_repository.dart';
import 'package:radio_flow/features/auth/data/profile_repository.dart';
import 'package:radio_flow/features/forum/data/forum_repository.dart';
import 'package:radio_flow/features/forum/data/offline_forum_repository.dart';
import 'package:radio_flow/features/forum/domain/forum_proposal.dart';
import 'package:radio_flow/features/tasks/data/offline_tasks_repository.dart';
import 'package:radio_flow/features/tasks/data/tasks_repository.dart';
import 'package:radio_flow/features/tasks/domain/task_models.dart';
import 'package:radio_flow/features/threads/data/offline_thread_repository.dart';
import 'package:radio_flow/features/threads/domain/thread_message.dart';
import 'package:sqlite3/sqlite3.dart';

const _offline = SocketException('Failed host lookup');

LocalStore memoryStore() => LocalStore(sqlite3.openInMemory());

class FakeConnectivity implements ConnectivityService {
  FakeConnectivity({this.online = true});
  bool online;
  final _ctrl = StreamController<bool>.broadcast();
  @override
  Future<bool> isOnline() async => online;
  @override
  Stream<bool> get changes => _ctrl.stream;
  void set(bool value) {
    online = value;
    _ctrl.add(value);
  }
}

class FakeTasksRemote implements TasksRepository {
  bool reachable = true;
  List<TeamTask> items = [];
  final calls = <String>[];
  final _ctrl = StreamController<void>.broadcast();

  void _check() {
    if (!reachable) throw _offline;
  }

  @override
  Stream<List<TeamTask>> watch() async* {
    _check();
    yield List.of(items);
    await for (final _ in _ctrl.stream) {
      yield List.of(items);
    }
  }

  @override
  Future<void> add({
    String? id,
    required String userId,
    required String title,
    DateTime? dueDate,
  }) async {
    _check();
    calls.add('add:$id:$title');
    if (items.any((t) => t.id == id)) throw const PostgrestLikeDuplicate();
    items = [
      TeamTask(
        id: id!,
        userId: userId,
        title: title,
        status: TaskStatus.todo,
        dueDate: dueDate,
      ),
      ...items,
    ];
    _ctrl.add(null);
  }

  @override
  Future<void> setStatus(String id, TaskStatus status) async {
    _check();
    calls.add('status:$id:${status.name}');
    items = [
      for (final t in items) t.id == id ? t.copyWith(status: status) : t,
    ];
    _ctrl.add(null);
  }

  @override
  Future<void> delete(String id) async {
    _check();
    calls.add('delete:$id');
    items = items.where((t) => t.id != id).toList();
    _ctrl.add(null);
  }
}

class PostgrestLikeDuplicate implements Exception {
  const PostgrestLikeDuplicate();
}

class FakeForumRemote implements ForumRepository {
  bool reachable = true;
  Object? failWith;
  final proposals = <ForumProposal>[];
  final calls = <String>[];
  @override
  Stream<List<ForumProposal>> watch() => Stream.value(List.of(proposals));
  @override
  Future<void> propose({
    String? id,
    required String authorId,
    required String title,
    required String angle,
    required ProposalFormat format,
    String? source,
  }) async {
    if (!reachable) throw _offline;
    if (failWith != null) throw failWith!;
    calls.add('propose:$id:$title');
  }

  @override
  Future<void> decide(String id, ProposalStatus status, {String? note}) async {}

  @override
  Future<void> linkToLine(String proposalId, String lineId) async {}
}

SyncService buildSync(
  LocalStore store,
  FakeConnectivity net,
  Map<String, OpHandler> handlers,
) => SyncService(
  store: store,
  connectivity: net,
  handlers: handlers,
  retryEvery: const Duration(hours: 1),
);

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  group('LocalStore', () {
    test('file d’attente : ordre, échecs, nouvelle tentative, purge', () async {
      final s = memoryStore();
      final a = await s.enqueue('x', {'n': 1});
      final b = await s.enqueue('y', {'n': 2});
      expect((await s.items()).map((i) => i.kind), ['x', 'y']);
      expect(await s.hasPending(), isTrue);

      await s.markFailed(a.id, 'refusé');
      var items = await s.items();
      expect(items.first.failed, isTrue);
      expect(items.first.attempts, 1);
      expect(await s.hasPending(), isTrue); // b reste en attente

      await s.retryFailed();
      expect((await s.items()).any((i) => i.failed), isFalse);

      await s.markFailed(a.id, 'refusé');
      await s.discardFailed();
      items = await s.items();
      expect(items.map((i) => i.id), [b.id]);
      s.dispose();
    });

    test(
      'cache : lecture, écriture, remplacement; purge sans perdre la file',
      () async {
        final s = memoryStore();
        expect(await s.readCache('k'), isNull);
        await s.writeCache('k', [
          {'a': 1},
        ]);
        await s.writeCache('k', [
          {'a': 2},
          {'a': 3},
        ]);
        expect((await s.readCache('k'))!.length, 2);
        await s.enqueue('x', {});
        await s.clearCache();
        expect(await s.readCache('k'), isNull);
        expect((await s.items()).length, 1);
        s.dispose();
      },
    );

    test('les données survivent à la fermeture de l’application', () async {
      final dir = Directory.systemTemp.createTempSync('radio_flow_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/db.sqlite';
      final first = LocalStore(sqlite3.open(path));
      await first.enqueue('task.add', {'id': 't1', 'title': 'Monter le son'});
      await first.writeCache('tasks', [
        {'id': 't0'},
      ]);
      first.dispose();

      final second = LocalStore(sqlite3.open(path));
      final items = await second.items();
      expect(items.single.payload['title'], 'Monter le son');
      expect((await second.readCache('tasks'))!.single['id'], 't0');
      second.dispose();
    });

    test('watch émet la file puis chaque changement', () async {
      final s = memoryStore();
      final seen = <int>[];
      final sub = s.watch().listen((l) => seen.add(l.length));
      await Future<void>.delayed(Duration.zero);
      await s.enqueue('x', {});
      await s.enqueue('x', {});
      await Future<void>.delayed(Duration.zero);
      expect(seen, [0, 1, 2]);
      await sub.cancel();
      s.dispose();
    });
  });

  group('SyncEngine', () {
    test('envoie dans l’ordre et vide la file', () async {
      final s = memoryStore();
      final sent = <String>[];
      await s.enqueue('a', {'v': '1'});
      await s.enqueue('a', {'v': '2'});
      final r = await SyncEngine(s, {
        'a': (p) async => sent.add(p['v'] as String),
      }).flush();
      expect(sent, ['1', '2']);
      expect(r.sent, 2);
      expect(await s.items(), isEmpty);
      s.dispose();
    });

    test('erreur réseau : s’arrête, conserve tout et garde l’ordre', () async {
      final s = memoryStore();
      final sent = <String>[];
      await s.enqueue('a', {'v': '1'});
      await s.enqueue('a', {'v': '2'});
      final r = await SyncEngine(s, {
        'a': (p) async {
          if (p['v'] == '1') throw _offline;
          sent.add(p['v'] as String);
        },
      }).flush();
      expect(r.stoppedOffline, isTrue);
      expect(sent, isEmpty); // la 2e ne passe pas devant la 1re
      final items = await s.items();
      expect(items.length, 2);
      expect(items.first.attempts, 1);
      s.dispose();
    });

    test('refus du serveur : marqué en échec, la suite continue', () async {
      final s = memoryStore();
      final sent = <String>[];
      await s.enqueue('a', {'v': '1'});
      await s.enqueue('a', {'v': '2'});
      final r = await SyncEngine(s, {
        'a': (p) async {
          if (p['v'] == '1') throw StateError('droits insuffisants');
          sent.add(p['v'] as String);
        },
      }).flush();
      expect(r.failed, 1);
      expect(sent, ['2']);
      final items = await s.items();
      expect(items.single.failed, isTrue);
      expect(items.single.error, contains('droits insuffisants'));
      s.dispose();
    });

    test('type d’opération inconnu : conservé, jamais perdu', () async {
      final s = memoryStore();
      await s.enqueue('inconnu', {});
      final r = await SyncEngine(s, {}).flush();
      expect(r.sent, 0);
      expect((await s.items()).length, 1);
      s.dispose();
    });

    test('classification des erreurs', () {
      expect(isNetworkError(const SocketException('x')), isTrue);
      expect(isNetworkError(TimeoutException('x')), isTrue);
      expect(isNetworkError(StateError('x')), isFalse);
    });
  });

  group('offlineFirst', () {
    Future<List<List<int>>> collect(
      Stream<List<int>> s, {
      int take = 1,
    }) async => (await s.take(take).toList()).map((x) => x).toList();

    test('affiche la copie locale puis les données du serveur', () async {
      final s = memoryStore();
      await s.writeCache('k', [
        {'v': 1},
      ]);
      final remote = StreamController<List<int>>();
      final out = <List<int>>[];
      final sub = offlineFirst<int>(
        store: s,
        key: 'k',
        remote: () => remote.stream,
        toJson: (x) => {'v': x},
        fromJson: (j) => j['v'] as int,
        overlay: (b, o) => b,
        reconnect: const Stream.empty(),
      ).listen(out.add);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      remote.add([5, 6]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(out, [
        [1],
        [5, 6],
      ]);
      expect((await s.readCache('k'))!.length, 2); // la copie est mise à jour
      await sub.cancel();
      await remote.close();
      s.dispose();
    });

    test(
      'sans réseau avec copie locale : la copie reste, puis reconnexion',
      () async {
        final s = memoryStore();
        await s.writeCache('k', [
          {'v': 1},
        ]);
        final reconnect = StreamController<void>.broadcast();
        var online = false;
        final out = <List<int>>[];
        final errors = <Object>[];
        final sub = offlineFirst<int>(
          store: s,
          key: 'k',
          remote: () => online ? Stream.value([9]) : Stream.error(_offline),
          toJson: (x) => {'v': x},
          fromJson: (j) => j['v'] as int,
          overlay: (b, o) => b,
          reconnect: reconnect.stream,
          retryAfter: const Duration(hours: 1),
        ).listen(out.add, onError: errors.add);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(out, [
          [1],
        ]);
        expect(errors, isEmpty);
        online = true;
        reconnect.add(null);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(out.last, [9]);
        await sub.cancel();
        s.dispose();
      },
    );

    test('sans réseau et sans copie : l’erreur est transmise', () async {
      final s = memoryStore();
      final errors = <Object>[];
      final sub = offlineFirst<int>(
        store: s,
        key: 'vide',
        remote: () => Stream.error(_offline),
        toJson: (x) => {'v': x},
        fromJson: (j) => j['v'] as int,
        overlay: (b, o) => b,
        reconnect: const Stream.empty(),
        retryAfter: const Duration(hours: 1),
      ).listen((_) {}, onError: errors.add);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(errors, isNotEmpty);
      await sub.cancel();
      s.dispose();
    });

    test(
      'collect helper',
      () async => expect(await collect(Stream.value([1])), [
        [1],
      ]),
    );
  });

  group('dépôts hors ligne', () {
    late LocalStore store;
    late FakeConnectivity net;
    late FakeForumRemote forum;
    late OfflineForumRepository repo;
    late SyncService sync;

    setUp(() {
      store = memoryStore();
      net = FakeConnectivity();
      forum = FakeForumRemote();
      sync = buildSync(store, net, {
        OfflineForumRepository.proposeKind: (p) =>
            OfflineForumRepository.sendPropose(forum, p),
      });
      repo = OfflineForumRepository(remote: forum, store: store, sync: sync);
    });
    tearDown(() async {
      await sync.dispose();
      store.dispose();
    });

    test('en ligne : envoi direct, rien en file', () async {
      await repo.propose(
        authorId: 'u1',
        title: 'Marché',
        angle: 'a',
        format: ProposalFormat.brief,
      );
      expect(forum.calls.single, startsWith('propose:'));
      expect(await store.items(), isEmpty);
    });

    test('sans réseau : mise en file avec un identifiant stable', () async {
      forum.reachable = false;
      await repo.propose(
        authorId: 'u1',
        title: 'Marché',
        angle: 'a',
        format: ProposalFormat.brief,
        source: 'AFP',
      );
      final op = (await store.items()).single;
      expect(op.kind, OfflineForumRepository.proposeKind);
      expect(op.payload['id'], isNotEmpty);
      expect(op.payload['source'], 'AFP');
    });

    test(
      'refus du serveur (pas le réseau) : l’erreur remonte, rien en file',
      () async {
        forum.failWith = StateError('droits');
        await expectLater(
          repo.propose(
            authorId: 'u1',
            title: 'x',
            angle: 'y',
            format: ProposalFormat.brief,
          ),
          throwsA(isA<StateError>()),
        );
        expect(await store.items(), isEmpty);
      },
    );

    test('file non vide : on s’ajoute à la file pour garder l’ordre', () async {
      forum.reachable = false;
      await repo.propose(
        authorId: 'u1',
        title: 'premier',
        angle: 'a',
        format: ProposalFormat.brief,
      );
      forum.reachable = true;
      await repo.propose(
        authorId: 'u1',
        title: 'second',
        angle: 'a',
        format: ProposalFormat.brief,
      );
      expect(forum.calls, isEmpty);
      expect((await store.items()).map((i) => i.payload['title']), [
        'premier',
        'second',
      ]);
    });

    test('surcouche : la proposition en attente apparaît, sans doublon après envoi', () async {
      forum.reachable = false;
      await repo.propose(
        authorId: 'u1',
        title: 'Marché',
        angle: 'a',
        format: ProposalFormat.brief,
      );
      final items = await store.items();
      final shown = OfflineForumRepository.overlay(const [], items);
      expect(shown.single.pendingSync, isTrue);
      expect(shown.single.status, ProposalStatus.pending);
      final server = ForumProposal(
        id: items.single.payload['id'] as String,
        authorId: 'u1',
        title: 'Marché',
        angle: 'a',
        format: ProposalFormat.brief,
        status: ProposalStatus.pending,
        createdAt: DateTime.now(),
      );
      expect(OfflineForumRepository.overlay([server], items).length, 1);
    });

    test(
      'tâches : la surcouche rejoue création, statut et suppression',
      () async {
        final base = [
          const TeamTask(
            id: 'a',
            userId: 'u1',
            title: 'Existante',
            status: TaskStatus.todo,
          ),
          const TeamTask(
            id: 'b',
            userId: 'u1',
            title: 'À supprimer',
            status: TaskStatus.todo,
          ),
        ];
        final s = memoryStore();
        await s.enqueue(OfflineTasksRepository.addKind, {
          'id': 'n',
          'user_id': 'u1',
          'title': 'Nouvelle',
        });
        await s.enqueue(OfflineTasksRepository.statusKind, {
          'id': 'a',
          'status': 'done',
        });
        await s.enqueue(OfflineTasksRepository.deleteKind, {'id': 'b'});
        final list = OfflineTasksRepository.overlay(base, await s.items());
        expect(list.map((t) => t.title), ['Nouvelle', 'Existante']);
        expect(list.first.pendingSync, isTrue);
        expect(list.last.status, TaskStatus.done);
        expect(list.last.pendingSync, isTrue);
        s.dispose();
      },
    );

    test(
      'fil : le message en attente est ajouté à la fin, seulement pour son fil',
      () async {
        final s = memoryStore();
        await s.enqueue(OfflineThreadRepository.sendKind, {
          'id': 'm1',
          'thread_id': 't1',
          'user_id': 'u1',
          'text': 'Son en route',
          'created_at': DateTime(2026, 9, 9).toIso8601String(),
        });
        final items = await s.items();
        final base = [
          ThreadMessage(
            id: 'x',
            userId: 'u2',
            createdAt: DateTime(2026, 9, 8),
            content: 'Avant',
          ),
        ];
        final t1 = OfflineThreadRepository.overlay('t1', base, items);
        expect(t1.map((m) => m.content), ['Avant', 'Son en route']);
        expect(t1.last.pendingSync, isTrue);
        expect(OfflineThreadRepository.overlay('t2', base, items).length, 1);
        s.dispose();
      },
    );
  });

  group('SyncService', () {
    test('envoie la file au retour du réseau et publie l’état', () async {
      final store = memoryStore();
      final net = FakeConnectivity(online: false);
      final sent = <String>[];
      final sync = buildSync(store, net, {
        'a': (p) async => sent.add(p['v'] as String),
      });
      final statuses = <SyncStatus>[];
      final sub = sync.status.listen(statuses.add);
      await sync.start();
      await store.enqueue('a', {'v': 'hors-ligne'});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(sent, isEmpty);
      expect(statuses.last.online, isFalse);
      expect(statuses.last.pending, 1);

      var reconnected = 0;
      final rsub = sync.reconnect.listen((_) => reconnected++);
      net.set(true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(sent, ['hors-ligne']);
      expect(reconnected, 1);
      expect(statuses.last.idle, isTrue);

      await sub.cancel();
      await rsub.cancel();
      await sync.dispose();
      store.dispose();
    });

    test(
      'un envoi qui échoue faute de réseau marque l’appareil hors ligne',
      () async {
        final store = memoryStore();
        final net = FakeConnectivity();
        final sync = buildSync(store, net, {'a': (p) async => throw _offline});
        await sync.start();
        await store.enqueue('a', {});
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(sync.current.online, isFalse);
        expect(sync.current.pending, 1);
        await sync.dispose();
        store.dispose();
      },
    );
  });

  testWidgets(
    'scénario complet : tâche créée sans réseau, envoyée au retour du réseau',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final store = memoryStore();
      final net = FakeConnectivity(online: false);
      final remote = FakeTasksRemote()..reachable = false;
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedIn()),
          profileRepositoryProvider.overrideWithValue(_Profiles()),
          localStoreProvider.overrideWithValue(store),
          connectivityServiceProvider.overrideWithValue(net),
          tasksRemoteProvider.overrideWithValue(remote),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const RadioFlowApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tâches').last);
      await tester.pumpAndSettle();

      // Hors ligne et sans copie locale : l'écran propose de réessayer, la création reste possible.
      expect(find.textContaining('Hors ligne'), findsOneWidget);
      await tester.tap(find.text('Nouvelle tâche'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Monter le reportage');
      await tester.tap(find.text('Créer'));
      await tester.pumpAndSettle();

      expect(remote.calls, isEmpty);
      expect((await store.items()).single.kind, OfflineTasksRepository.addKind);
      expect(find.textContaining('1 modification en attente'), findsOneWidget);

      // Le réseau revient : envoi automatique, bandeau disparu, tâche affichée sans marqueur.
      remote.reachable = true;
      net.set(true);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(remote.calls.single, startsWith('add:'));
      expect(await store.items(), isEmpty);
      expect(find.textContaining('Hors ligne'), findsNothing);
      expect(find.text('Monter le reportage'), findsOneWidget);
      expect(find.text('En attente d’envoi'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _SignedIn implements AuthRepository {
  @override
  Future<void> changePassword({
    required String email,
    required String current,
    required String next,
  }) async {}
  @override
  Stream<bool> signedIn() => Stream.value(true);
  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}
  @override
  Future<void> signOut() async {}
}

class _Profiles implements ProfileRepository {
  @override
  Future<Profile?> fetchMe() async =>
      const Profile(id: 'u1', fullName: 'Awa', role: UserRole.journalist);
  @override
  Future<Map<String, String>> fetchNames() async => {'u1': 'Awa'};
}
