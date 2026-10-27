import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:radio_flow/app.dart';
import 'package:radio_flow/data/local/local_store.dart';
import 'package:radio_flow/data/local/sql_local_store.dart';
import 'package:radio_flow/data/sync/connectivity_service.dart';
import 'package:radio_flow/features/auth/data/auth_repository.dart';
import 'package:radio_flow/features/auth/data/profile_repository.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AccountAuth implements AuthRepository {
  final _ctrl = StreamController<bool>.broadcast();
  bool _in = true;
  Object? changeError;
  final changes = <String>[];

  @override
  Stream<bool> signedIn() async* {
    yield _in;
    yield* _ctrl.stream;
  }

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}
  @override
  Future<void> signOut() async {
    _in = false;
    _ctrl.add(false);
  }

  @override
  Future<void> changePassword({
    required String email,
    required String current,
    required String next,
  }) async {
    if (changeError != null) throw changeError!;
    changes.add('$email|$current|$next');
  }
}

class OfflineNet implements ConnectivityService {
  @override
  Future<bool> isOnline() async => false;
  @override
  Stream<bool> get changes => const Stream.empty();
}

class BrokenProfiles implements ProfileRepository {
  @override
  Future<Profile?> fetchMe() async => throw Exception('hors ligne');
  @override
  Future<Map<String, String>> fetchNames() async =>
      throw Exception('hors ligne');
}

class Profiles implements ProfileRepository {
  @override
  Future<Profile?> fetchMe() async => const Profile(
    id: 'u1',
    fullName: 'Chadrack Tambwe Londe',
    role: UserRole.admin,
    email: 'chadracktambwe@gmail.com',
  );
  @override
  Future<Map<String, String>> fetchNames() async => {
    'u1': 'Chadrack Tambwe Londe',
  };
}

Future<(AccountAuth, LocalStore)> pump(
  WidgetTester tester, {
  ProfileRepository? profiles,
}) async {
  await initializeDateFormatting('fr');
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final auth = AccountAuth();
  final store = SqlLocalStore(sqlite3.openInMemory());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(profiles ?? Profiles()),
        localStoreProvider.overrideWithValue(store),
        connectivityServiceProvider.overrideWithValue(OfflineNet()),
      ],
      child: const RadioFlowApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Mon compte'));
  await tester.pumpAndSettle();
  return (auth, store);
}

Future<void> fill(
  WidgetTester tester, {
  String current = 'ancien-mdp-1',
  String next = 'NouveauMdp2026',
  String? confirm,
}) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), current);
  await tester.enterText(fields.at(1), next);
  await tester.enterText(fields.at(2), confirm ?? next);
}

Future<void> submit(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Modifier le mot de passe'));
  await tester.tap(find.text('Modifier le mot de passe'));
  await tester.pumpAndSettle();
}

void main() {
  group('règles du nouveau mot de passe', () {
    test('longueur, lettres et chiffres, différent de l’actuel', () {
      expect(validateNewPassword('court1'), contains('10 caractères'));
      expect(validateNewPassword('uniquementdeslettres'), contains('chiffres'));
      expect(validateNewPassword('12345678901234'), contains('lettres'));
      expect(
        validateNewPassword('MotDePasse2026', current: 'MotDePasse2026'),
        contains('différent'),
      );
      expect(validateNewPassword('MotDePasse2026', current: 'autre'), isNull);
    });
    test('messages d’erreur', () {
      expect(
        passwordChangeErrorMessage(
          const AuthException('Invalid login credentials'),
        ),
        'Mot de passe actuel incorrect.',
      );
      expect(
        passwordChangeErrorMessage(
          const AuthException(
            'New password should be different from the old password.',
          ),
        ),
        contains('différent'),
      );
      expect(
        passwordChangeErrorMessage(
          const AuthException('Password should be at least 6 characters'),
        ),
        contains('trop faible'),
      );
      expect(
        passwordChangeErrorMessage(Exception('réseau')),
        contains('réseau'),
      );
    });
  });

  testWidgets('affiche le profil et le rôle', (tester) async {
    await pump(tester);
    expect(find.text('Chadrack Tambwe Londe'), findsOneWidget);
    expect(find.text('chadracktambwe@gmail.com'), findsOneWidget);
    expect(find.text('Rédacteur en chef'), findsOneWidget);
    expect(find.text('CL'), findsOneWidget); // initiales
  });

  testWidgets(
    'validation : champs vides, mot de passe faible, confirmation différente',
    (tester) async {
      final (auth, _) = await pump(tester);
      await submit(tester);
      expect(find.text('Saisissez votre mot de passe actuel.'), findsOneWidget);
      expect(find.text('Au moins 10 caractères.'), findsOneWidget);

      await fill(tester, next: 'NouveauMdp2026', confirm: 'Autre1234567');
      await submit(tester);
      expect(
        find.text('Les deux mots de passe ne correspondent pas.'),
        findsOneWidget,
      );
      expect(auth.changes, isEmpty);
    },
  );

  testWidgets('changement réussi : confirmation et champs vidés', (
    tester,
  ) async {
    final (auth, _) = await pump(tester);
    await fill(tester);
    await submit(tester);
    expect(
      auth.changes.single,
      'chadracktambwe@gmail.com|ancien-mdp-1|NouveauMdp2026',
    );
    expect(find.text('Mot de passe modifié.'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(1))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets(
    'mot de passe actuel incorrect : message clair, rien de modifié',
    (tester) async {
      final (auth, _) = await pump(tester);
      auth.changeError = const AuthException('Invalid login credentials');
      await fill(tester);
      await submit(tester);
      expect(find.text('Mot de passe actuel incorrect.'), findsOneWidget);
      expect(find.text('Mot de passe modifié.'), findsNothing);
    },
  );

  testWidgets(
    'déconnexion : retour à l’écran de connexion, copie locale effacée',
    (tester) async {
      final (_, store) = await pump(tester);
      await store.writeCache('tasks', [
        {'id': 't'},
      ]);
      await tester.ensureVisible(find.text('Se déconnecter'));
      await tester.tap(find.text('Se déconnecter'));
      await tester.pumpAndSettle();
      expect(find.text('Se connecter'), findsOneWidget);
      expect(await store.readCache('tasks'), isNull);
    },
  );

  testWidgets(
    'déconnexion avec envois en attente : confirmation, file conservée',
    (tester) async {
      final (_, store) = await pump(tester);
      await store.enqueue('task.add', {
        'id': 'x',
        'user_id': 'u1',
        'title': 'En attente',
      });
      await tester.pump(const Duration(milliseconds: 50));
      await tester.ensureVisible(find.text('Se déconnecter'));
      await tester.tap(find.text('Se déconnecter'));
      await tester.pumpAndSettle();
      expect(find.text('Modifications non envoyées'), findsOneWidget);

      await tester.tap(find.text('Rester connecté'));
      await tester.pumpAndSettle();
      expect(find.text('Mon compte'), findsWidgets);

      await tester.tap(find.text('Se déconnecter'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Se déconnecter'));
      await tester.pumpAndSettle();
      expect(find.text('Se connecter'), findsOneWidget);
      expect((await store.items()).length, 1); // la rédaction n'est pas perdue
      await tester.pumpWidget(const SizedBox());
    },
  );
}
