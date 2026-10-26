import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:radio_flow/app.dart';
import 'package:radio_flow/features/auth/data/auth_repository.dart';
import 'package:radio_flow/features/auth/data/profile_repository.dart';
import 'package:radio_flow/features/notifications/data/push_service.dart';

import 'conductor_test.dart' as ct;

class FakePush implements PushService {
  FakePush({this.available = true});
  final bool available;
  final registered = <String>[];
  int unregisterCalls = 0;
  final _opened = StreamController<Map<String, String>>.broadcast();

  void tap(Map<String, String> data) => _opened.add(data);

  @override
  Future<bool> register(String userId) async {
    registered.add(userId);
    return available;
  }

  @override
  Future<void> unregister() async => unregisterCalls++;

  @override
  Stream<Map<String, String>> get opened => _opened.stream;
}

Future<FakePush> pumpWith(WidgetTester tester, {bool available = true}) async {
  await initializeDateFormatting('fr');
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final push = FakePush(available: available);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(ct.SignedIn()),
        profileRepositoryProvider.overrideWithValue(
          ct.Profiles(UserRole.journalist),
        ),
        pushServiceProvider.overrideWithValue(push),
      ],
      child: const RadioFlowApp(),
    ),
  );
  await tester.pumpAndSettle();
  return push;
}

void main() {
  test('écran ouvert selon la notification touchée', () {
    expect(routeForNotification({'ref_type': 'proposal'}), '/forum');
    expect(routeForNotification({'ref_type': 'message'}), '/sound');
    expect(routeForNotification({'ref_type': ''}), isNull);
    expect(routeForNotification(const {}), isNull);
  });

  testWidgets(
    'l’appareil est enregistré une fois pour l’utilisateur connecté',
    (tester) async {
      final push = await pumpWith(tester);
      expect(push.registered, ['u1']);
    },
  );

  testWidgets(
    'refus ou Firebase absent : l’application fonctionne quand même',
    (tester) async {
      final push = await pumpWith(tester, available: false);
      expect(push.registered, ['u1']);
      expect(find.text('Forum'), findsWidgets);
    },
  );

  testWidgets('toucher une notification ouvre l’écran concerné', (
    tester,
  ) async {
    final push = await pumpWith(tester);
    push.tap({'ref_type': 'message', 'ref_id': 'm1'});
    await tester.pumpAndSettle();
    expect(find.text('Espace Son'), findsWidgets);
  });

  testWidgets('la déconnexion retire l’appareil du compte', (tester) async {
    final push = await pumpWith(tester);
    await tester.tap(find.byTooltip('Mon compte'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Se déconnecter'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Se déconnecter'));
    await tester.pumpAndSettle();
    expect(push.unregisterCalls, 1);
  });
}
