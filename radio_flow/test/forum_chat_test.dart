import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:radio_flow/app.dart';
import 'package:radio_flow/features/auth/data/auth_repository.dart';
import 'package:radio_flow/features/auth/data/profile_repository.dart';
import 'package:radio_flow/features/forum/data/forum_repository.dart';
import 'package:radio_flow/features/forum_chat/data/forum_chat_repository.dart';
import 'package:radio_flow/features/forum_chat/domain/forum_post.dart';

import 'forum_test.dart' as ft;

class FakeForumChat implements ForumChatRepository {
  final posts = <ForumPost>[
    ForumPost(
      id: 'p1',
      isSystem: true,
      content: 'Bonjour à tous, n’oubliez pas de poster vos sujets.',
      createdAt: DateTime(2026, 11, 25, 8),
    ),
    ForumPost(
      id: 'p2',
      authorId: 'u2',
      content: 'Quelqu’un a vu le match hier ?',
      createdAt: DateTime(2026, 11, 25, 9),
    ),
  ];
  final sent = <String>[];
  final deleted = <String>[];
  final _ctrl = StreamController<List<ForumPost>>.broadcast();

  List<ForumPost> get _sorted =>
      (List.of(posts)..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  @override
  Stream<List<ForumPost>> watch() async* {
    yield _sorted;
    yield* _ctrl.stream;
  }

  @override
  Future<void> send({required String authorId, required String content}) async {
    sent.add(content);
    posts.add(
      ForumPost(
        id: 'n${posts.length}',
        authorId: authorId,
        content: content,
        createdAt: DateTime(2026, 11, 25, 10),
      ),
    );
    _ctrl.add(_sorted);
  }

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    posts.removeWhere((p) => p.id == id);
    _ctrl.add(_sorted);
  }
}

Future<FakeForumChat> pump(WidgetTester tester, UserRole role) async {
  await initializeDateFormatting('fr');
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final chat = FakeForumChat();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(ft.SignedInAuth()),
        profileRepositoryProvider.overrideWithValue(ft.FakeProfiles(role)),
        forumRepositoryProvider.overrideWithValue(ft.FakeForum()),
        forumChatRepositoryProvider.overrideWithValue(chat),
      ],
      child: const RadioFlowApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Forum').last);
  await tester.pumpAndSettle();
  return chat;
}

void main() {
  testWidgets('le Forum libre affiche les messages et le rappel « Radio Flow »', (
    tester,
  ) async {
    await pump(tester, UserRole.journalist);
    expect(find.text('Radio Flow'), findsOneWidget);
    expect(find.textContaining('n’oubliez pas de poster'), findsOneWidget);
    expect(find.text('Quelqu’un a vu le match hier ?'), findsOneWidget);
    expect(find.text('Moussa Keita'), findsOneWidget);
    // les propositions de sujets ne sont plus dans le Forum
    expect(find.text('Proposer un sujet'), findsNothing);
  });

  testWidgets('un membre peut écrire au forum', (tester) async {
    final chat = await pump(tester, UserRole.technician);
    await tester.enterText(find.byType(TextField), 'Bonjour la radio');
    await tester.tap(find.byTooltip('Envoyer le message'));
    await tester.pumpAndSettle();
    expect(chat.sent, ['Bonjour la radio']);
    expect(find.text('Bonjour la radio'), findsWidgets);
  });

  testWidgets('seul le rédacteur en chef supprime les messages des autres', (
    tester,
  ) async {
    await pump(tester, UserRole.journalist);
    expect(find.byTooltip('Supprimer le message'), findsNothing);
  });

  testWidgets('le rédacteur en chef peut supprimer un message', (tester) async {
    final chat = await pump(tester, UserRole.admin);
    await tester.tap(find.byTooltip('Supprimer le message'));
    await tester.pumpAndSettle();
    expect(chat.deleted, ['p2']);
  });
}
