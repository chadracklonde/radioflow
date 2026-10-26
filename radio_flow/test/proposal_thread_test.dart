import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:radio_flow/app.dart';
import 'package:radio_flow/data/local/local_store.dart';
import 'package:radio_flow/data/sync/sync_service.dart';
import 'package:radio_flow/features/auth/data/auth_repository.dart';
import 'package:radio_flow/features/auth/data/profile_repository.dart';
import 'package:radio_flow/features/conductor/data/conductor_repository.dart';
import 'package:radio_flow/features/forum/data/forum_repository.dart';
import 'package:radio_flow/features/forum/domain/forum_proposal.dart';
import 'package:radio_flow/features/threads/data/offline_thread_repository.dart';
import 'package:radio_flow/features/threads/data/thread_repository.dart';
import 'package:radio_flow/features/threads/domain/thread_message.dart';
import 'package:sqlite3/sqlite3.dart';

import 'conductor_test.dart' as ct;
import 'offline_test.dart' as ot;
import 'team_test.dart' as tt;

ForumProposal proposal(
  String id,
  String title,
  ProposalStatus status, {
  String? line,
}) => ForumProposal(
  id: id,
  authorId: 'u2',
  title: title,
  angle: 'angle',
  format: ProposalFormat.interview,
  status: status,
  createdAt: DateTime(2026, 9, 9, 8),
  conductorLineId: line,
);

class FakeForum implements ForumRepository {
  final proposals = [
    proposal('p1', 'Marché de Bamako', ProposalStatus.approved),
    proposal('p2', 'Sujet en attente', ProposalStatus.pending),
    proposal('p3', 'Crue du fleuve', ProposalStatus.approved, line: 'l1'),
    proposal('p4', 'Sujet refusé', ProposalStatus.rejected),
  ];
  final links = <String>[];
  Object? linkError;

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
  }) async {}
  @override
  Future<void> decide(String id, ProposalStatus status, {String? note}) async {}
  @override
  Future<void> linkToLine(String proposalId, String lineId) async {
    if (linkError != null) throw linkError!;
    links.add('$proposalId:$lineId');
  }
}

class FakeThreads implements ThreadRepository {
  final sent = <String>[];
  @override
  Future<String> threadIdForLine(String lineId) async => 't-$lineId';
  @override
  Future<String> threadIdForProposal(String proposalId) async =>
      'tp-$proposalId';
  @override
  Stream<List<ThreadMessage>> watchMessages(String threadId) => Stream.value([
    ThreadMessage(
      id: 'm1',
      userId: 'u2',
      createdAt: DateTime(2026, 9, 9, 9),
      content: 'Premier détail ($threadId)',
    ),
  ]);
  @override
  Future<void> sendText({
    String? id,
    required String threadId,
    required String userId,
    required String text,
  }) async {
    sent.add('$threadId|$userId|$text');
  }
}

class Env {
  Env(this.forum, this.threads, this.conductors);
  final FakeForum forum;
  final FakeThreads threads;
  final ct.FakeConductors conductors;
}

Future<Env> pump(
  WidgetTester tester, {
  UserRole role = UserRole.journalist,
  bool superAdmin = false,
  void Function(FakeForum forum)? prepare,
}) async {
  await initializeDateFormatting('fr');
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final forum = FakeForum();
  prepare?.call(forum);
  final env = Env(
    forum,
    FakeThreads(),
    ct.FakeConductors(
      conductors: [ct.Conductor0.today()],
      lines: ct.linesForTest,
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(tt.TestAuth()),
        profileRepositoryProvider.overrideWithValue(
          tt.TestProfiles(role, superAdmin: superAdmin),
        ),
        forumRepositoryProvider.overrideWithValue(env.forum),
        threadRepositoryProvider.overrideWithValue(env.threads),
        conductorRepositoryProvider.overrideWithValue(env.conductors),
      ],
      child: const RadioFlowApp(),
    ),
  );
  await tester.pumpAndSettle();
  return env;
}

Future<void> openDiscussion(
  WidgetTester tester,
  String title, {
  bool scroll = false,
}) async {
  if (scroll) {
    // La liste défile : sinon le bouton d'une carte basse reste sous « Proposer un sujet ».
    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
    await tester.pumpAndSettle();
  }
  final card = find
      .ancestor(of: find.text(title), matching: find.byType(Card))
      .first;
  final button = find.descendant(
    of: card,
    matching: find.text('Ouvrir la discussion'),
  );

  await tester.tap(button);
  await tester.pumpAndSettle();
}

bool composerEnabled(WidgetTester tester) {
  final field = tester.widget<TextField>(find.byType(TextField));
  final send = tester.widget<IconButton>(
    find.widgetWithIcon(IconButton, Icons.send),
  );
  return field.enabled != false && !field.readOnly && send.onPressed != null;
}

void main() {
  testWidgets('seul un sujet validé offre l’accès à sa discussion', (
    tester,
  ) async {
    await pump(tester);
    expect(
      find.text('Ouvrir la discussion'),
      findsNWidgets(2),
    ); // p1 et p3, validés
    final pending = find
        .ancestor(
          of: find.text('Sujet en attente'),
          matching: find.byType(Card),
        )
        .first;
    expect(
      find.descendant(of: pending, matching: find.text('Ouvrir la discussion')),
      findsNothing,
    );
    final rejected = find
        .ancestor(of: find.text('Sujet refusé'), matching: find.byType(Card))
        .first;
    expect(
      find.descendant(
        of: rejected,
        matching: find.text('Ouvrir la discussion'),
      ),
      findsNothing,
    );
  });

  for (final (role, label) in [
    (UserRole.journalist, 'journaliste'),
    (UserRole.technician, 'technicien'),
    (UserRole.admin, 'rédacteur en chef'),
  ]) {
    testWidgets(
      'sujet validé : le $label peut écrire (saisie et envoi actifs)',
      (tester) async {
        final env = await pump(tester, role: role);
        await openDiscussion(tester, 'Marché de Bamako');

        expect(find.text('Premier détail (tp-p1)'), findsOneWidget);
        expect(
          composerEnabled(tester),
          isTrue,
          reason: 'le statut « validé » ne doit rien verrouiller',
        );

        await tester.enterText(
          find.byType(TextField),
          'Détail de l’information',
        );
        await tester.tap(find.byTooltip('Envoyer'));
        await tester.pumpAndSettle();
        expect(env.threads.sent, ['tp-p1|u1|Détail de l’information']);
      },
    );
  }

  testWidgets(
    'sujet non encore placé : texte libre, pas d’envoi de son, rappel affiché',
    (tester) async {
      await pump(tester);
      await openDiscussion(tester, 'Marché de Bamako');
      expect(
        find.textContaining('toute l’équipe peut écrire ici'),
        findsOneWidget,
      );
      expect(find.textContaining('une fois le sujet placé'), findsOneWidget);
      expect(find.byTooltip('Envoyer un fichier audio'), findsNothing);
    },
  );

  testWidgets(
    'sujet placé dans un conducteur : le rappel renvoie vers la ligne',
    (tester) async {
      await pump(tester);
      await openDiscussion(tester, 'Crue du fleuve', scroll: true);
      expect(find.textContaining('placé dans un conducteur'), findsOneWidget);
      expect(composerEnabled(tester), isTrue);
    },
  );

  testWidgets(
    'placer un sujet validé : choix dans le formulaire, titre prérempli, fil rattaché',
    (tester) async {
      final env = await pump(tester, role: UserRole.admin);
      await tester.tap(find.text('Conducteur').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Journal de 12h'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajouter une ligne'));
      await tester.pumpAndSettle();

      // seuls les sujets validés et pas encore placés sont proposés (p1; p3 est déjà placé)
      await tester.tap(find.text('Aucun'));
      await tester.pumpAndSettle();
      expect(find.text('Marché de Bamako').last, findsOneWidget);
      expect(find.text('Crue du fleuve'), findsNothing);
      expect(find.text('Sujet en attente'), findsNothing);
      await tester.tap(find.text('Marché de Bamako').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'Marché de Bamako',
      );

      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();
      expect(env.conductors.calls, contains('add:Marché de Bamako:-'));
      expect(env.forum.links, [
        'p1:l3',
      ]); // la nouvelle ligne est la 3e du conducteur de test
    },
  );

  testWidgets('sans sujet à placer, le formulaire de ligne reste simple', (
    tester,
  ) async {
    await pump(
      tester,
      role: UserRole.admin,
      prepare: (f) => f.proposals.removeWhere((p) => p.id == 'p1'),
    );
    await tester.tap(find.text('Conducteur').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Journal de 12h'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter une ligne'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sujet validé (facultatif)'), findsNothing);
  });

  testWidgets(
    'échec du rattachement : la ligne est créée et l’utilisateur est prévenu',
    (tester) async {
      final env = await pump(tester, role: UserRole.admin);
      env.forum.linkError = Exception('réseau');
      await tester.tap(find.text('Conducteur').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Journal de 12h'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajouter une ligne'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aucun'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Marché de Bamako').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();
      expect(env.conductors.calls, contains('add:Marché de Bamako:-'));
      expect(find.textContaining('n’a pas pu y être lié'), findsOneWidget);
    },
  );

  group('fil d’un sujet hors ligne', () {
    test('l’identifiant du fil est mémorisé et retrouvé sans réseau', () async {
      final store = LocalStore(sqlite3.openInMemory());
      final net = ot.FakeConnectivity();
      final sync = SyncService(
        store: store,
        connectivity: net,
        handlers: const {},
      );
      final remote = _FlakyThreads();
      final repo = OfflineThreadRepository(
        remote: remote,
        store: store,
        sync: sync,
      );

      expect(await repo.threadIdForProposal('p1'), 'tp-p1');
      remote.reachable = false;
      expect(
        await repo.threadIdForProposal('p1'),
        'tp-p1',
        reason: 'servi depuis la copie locale',
      );
      await expectLater(
        repo.threadIdForProposal('inconnu'),
        throwsA(isA<SocketException>()),
      );

      await sync.dispose();
      store.dispose();
    });
  });
}

class _FlakyThreads extends FakeThreads {
  bool reachable = true;
  @override
  Future<String> threadIdForProposal(String proposalId) async {
    if (!reachable) throw const SocketException('Failed host lookup');
    return super.threadIdForProposal(proposalId);
  }
}
