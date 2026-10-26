import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:radio_flow/app.dart';
import 'package:radio_flow/features/auth/data/auth_repository.dart';
import 'package:radio_flow/features/auth/data/profile_repository.dart';
import 'package:radio_flow/features/notifications/data/notification_repository.dart';

import 'conductor_test.dart' as ct;

class FakeNotifications implements NotificationRepository {
  FakeNotifications(this.items);
  List<AppNotification> items;
  final _changes = StreamController<void>.broadcast();
  int markCalls = 0;

  @override
  Stream<List<AppNotification>> watch() async* {
    yield List.of(items);
    await for (final _ in _changes.stream) {
      yield List.of(items);
    }
  }

  @override
  Future<void> markAllRead() async {
    markCalls++;
    items = [
      for (final n in items)
        n.unread
            ? AppNotification(
                id: n.id,
                kind: n.kind,
                title: n.title,
                body: n.body,
                refType: n.refType,
                refId: n.refId,
                createdAt: n.createdAt,
                readAt: DateTime.now(),
              )
            : n,
    ];
    _changes.add(null);
  }
}

AppNotification _n(
  String id,
  String kind,
  String title, {
  bool unread = true,
}) => AppNotification(
  id: id,
  kind: kind,
  title: title,
  body: 'Barrage de Sélingué',
  refType: kind.startsWith('proposal') ? 'proposal' : 'message',
  createdAt: DateTime(2026, 9, 9, 9, 30),
  readAt: unread ? null : DateTime(2026, 9, 9, 10),
);

Future<FakeNotifications> pump(
  WidgetTester tester,
  List<AppNotification> items,
) async {
  await initializeDateFormatting('fr');
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = FakeNotifications(items);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(ct.SignedIn()),
        profileRepositoryProvider.overrideWithValue(
          ct.Profiles(UserRole.admin),
        ),
        notificationRepositoryProvider.overrideWithValue(repo),
      ],
      child: const RadioFlowApp(),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('cloche : nombre de notifications non lues', (tester) async {
    await pump(tester, [
      _n('1', 'proposal.new', 'Nouveau sujet proposé'),
      _n('2', 'sound.new', 'Nouveau son reçu'),
      _n('3', 'proposal.approved', 'Sujet validé', unread: false),
    ]);
    expect(find.byTooltip('Notifications (2 non lues)'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('cloche sans notification', (tester) async {
    await pump(tester, const []);
    expect(find.byTooltip('Notifications'), findsOneWidget);
  });

  testWidgets('l’écran liste les notifications et les marque comme lues', (
    tester,
  ) async {
    final repo = await pump(tester, [
      _n('1', 'proposal.new', 'Nouveau sujet proposé'),
      _n('2', 'proposal.approved', 'Sujet validé', unread: false),
    ]);
    await tester.tap(find.byTooltip('Notifications (1 non lue)'));
    await tester.pumpAndSettle();
    expect(find.text('Nouveau sujet proposé'), findsOneWidget);
    expect(find.text('Sujet validé'), findsOneWidget);
    expect(find.byIcon(Icons.circle), findsOneWidget);
    expect(repo.markCalls, 1);
    // la mise en évidence reste pendant la visite, le compteur est remis à zéro
    expect(find.byIcon(Icons.circle), findsOneWidget);
  });

  testWidgets('écran vide', (tester) async {
    await pump(tester, const []);
    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();
    expect(find.text('Aucune notification pour le moment.'), findsOneWidget);
  });
}
