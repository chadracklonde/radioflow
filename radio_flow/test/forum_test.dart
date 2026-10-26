import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:radio_flow/app.dart';
import 'package:radio_flow/features/auth/data/auth_repository.dart';
import 'package:radio_flow/features/auth/data/profile_repository.dart';
import 'package:radio_flow/features/forum/data/forum_repository.dart';
import 'package:radio_flow/features/forum/domain/forum_proposal.dart';

class SignedInAuth implements AuthRepository {
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

class FakeProfiles implements ProfileRepository {
  FakeProfiles(this.role);
  final UserRole role;
  @override
  Future<Profile?> fetchMe() async =>
      Profile(id: 'u1', fullName: 'Awa Traoré', role: role);
  @override
  Future<Map<String, String>> fetchNames() async => {
    'u1': 'Awa Traoré',
    'u2': 'Moussa Keita',
  };
}

class FakeForum implements ForumRepository {
  final _items = <ForumProposal>[
    ForumProposal(
      id: 'p1',
      authorId: 'u2',
      title: 'Marché de Bamako',
      angle: 'Hausse des prix',
      format: ProposalFormat.interview,
      status: ProposalStatus.pending,
      createdAt: DateTime(2026, 9, 9, 8),
    ),
    ForumProposal(
      id: 'p2',
      authorId: 'u2',
      title: 'Crue du fleuve',
      angle: 'Reportage terrain',
      format: ProposalFormat.article,
      status: ProposalStatus.approved,
      createdAt: DateTime(2026, 9, 8, 8),
    ),
  ];
  final _ctrl = StreamController<List<ForumProposal>>.broadcast();
  final decisions = <String>[];
  final links = <String>[];
  final proposed = <String>[];

  @override
  Stream<List<ForumProposal>> watch() async* {
    yield List.of(_items);
    yield* _ctrl.stream;
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
    proposed.add(title);
  }

  @override
  Future<void> decide(String id, ProposalStatus status, {String? note}) async {
    decisions.add('$id:${status.dbValue}:${note ?? ''}');
  }

  @override
  Future<void> linkToLine(String proposalId, String lineId) async {
    links.add('$proposalId:$lineId');
  }
}

Future<FakeForum> pump(WidgetTester tester, UserRole role) async {
  await initializeDateFormatting('fr');
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final forum = FakeForum();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(SignedInAuth()),
        profileRepositoryProvider.overrideWithValue(FakeProfiles(role)),
        forumRepositoryProvider.overrideWithValue(forum),
      ],
      child: const RadioFlowApp(),
    ),
  );
  await tester.pumpAndSettle();
  return forum;
}

void main() {
  testWidgets(
    'journaliste : voit les propositions, peut proposer, ne peut pas décider',
    (tester) async {
      final forum = await pump(tester, UserRole.journalist);
      expect(find.text('Marché de Bamako'), findsOneWidget);
      expect(find.text('Crue du fleuve'), findsOneWidget);
      expect(find.text('Valider'), findsNothing);

      await tester.tap(find.text('Proposer un sujet'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Envoyer'));
      await tester.pumpAndSettle();
      expect(find.text('Donnez un titre au sujet.'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), 'Nouveau sujet');
      await tester.enterText(find.byType(TextFormField).at(1), 'Un angle');
      await tester.tap(find.text('Envoyer'));
      await tester.pumpAndSettle();
      expect(forum.proposed, ['Nouveau sujet']);
    },
  );

  testWidgets('filtre par statut', (tester) async {
    await pump(tester, UserRole.journalist);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Validé'));
    await tester.pumpAndSettle();
    expect(find.text('Marché de Bamako'), findsNothing);
    expect(find.text('Crue du fleuve'), findsOneWidget);
  });

  testWidgets('rédacteur en chef : valide et refuse avec note', (tester) async {
    final forum = await pump(tester, UserRole.admin);
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(forum.decisions, ['p1:approved:']);

    await tester.tap(find.text('Refuser'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Déjà traité');
    await tester.tap(find.text('Confirmer'));
    await tester.pumpAndSettle();
    expect(forum.decisions.last, 'p1:rejected:Déjà traité');
  });

  testWidgets('technicien : lecture seule', (tester) async {
    await pump(tester, UserRole.technician);
    expect(find.text('Marché de Bamako'), findsOneWidget);
    expect(find.text('Proposer un sujet'), findsNothing);
    expect(find.text('Valider'), findsNothing);
  });
}
