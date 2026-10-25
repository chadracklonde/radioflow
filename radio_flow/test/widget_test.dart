import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radio_flow/app.dart';
import 'package:radio_flow/features/auth/data/auth_repository.dart';

class FakeAuth implements AuthRepository {
  @override
  Future<void> changePassword({
    required String email,
    required String current,
    required String next,
  }) async {}
  final _ctrl = StreamController<bool>.broadcast();
  bool _in = false;
  String? failWith;

  @override
  Stream<bool> signedIn() async* {
    yield _in;
    yield* _ctrl.stream;
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    if (failWith != null) throw Exception(failWith);
    _in = true;
    _ctrl.add(true);
  }

  @override
  Future<void> signOut() async {
    _in = false;
    _ctrl.add(false);
  }
}

Future<FakeAuth> pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final auth = FakeAuth();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(auth)],
      child: const RadioFlowApp(),
    ),
  );
  await tester.pumpAndSettle();
  return auth;
}

Future<void> login(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).at(0), 'a@rtc.ml');
  await tester.enterText(find.byType(TextFormField).at(1), 'secret');
  await tester.tap(find.text('Se connecter'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('non connecté : écran de connexion, validation des champs', (
    tester,
  ) async {
    await pump(tester, const Size(400, 800));
    expect(find.text('Se connecter'), findsOneWidget);
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();
    expect(find.text('Saisissez votre email.'), findsOneWidget);
    expect(find.text('Saisissez votre mot de passe.'), findsOneWidget);
  });

  testWidgets(
    'téléphone : barre de navigation basse après connexion, puis déconnexion',
    (tester) async {
      await pump(tester, const Size(400, 800));
      await login(tester);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      await tester.tap(find.text('Tâches'));
      await tester.pumpAndSettle();
      expect(find.text('Tâches'), findsWidgets);
      await tester.tap(find.byTooltip('Mon compte'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Se déconnecter'));
      await tester.tap(find.text('Se déconnecter'));
      await tester.pumpAndSettle();
      expect(find.text('Se connecter'), findsOneWidget);
    },
  );

  testWidgets('bureau : rail latéral', (tester) async {
    await pump(tester, const Size(1300, 800));
    await login(tester);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('erreur de connexion affichée', (tester) async {
    final auth = await pump(tester, const Size(400, 800));
    auth.failWith = 'boom';
    await login(tester);
    expect(
      find.text('Connexion impossible. Vérifiez votre réseau et réessayez.'),
      findsOneWidget,
    );
  });
}
