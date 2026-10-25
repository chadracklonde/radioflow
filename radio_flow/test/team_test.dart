import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:radio_flow/app.dart';
import 'package:radio_flow/features/auth/data/auth_repository.dart';
import 'package:radio_flow/features/auth/data/profile_repository.dart';
import 'package:radio_flow/features/team/data/team_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TestAuth implements AuthRepository {
  @override
  Stream<bool> signedIn() => Stream.value(true);
  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<void> changePassword({
    required String email,
    required String current,
    required String next,
  }) async {}
}

class TestProfiles implements ProfileRepository {
  TestProfiles(this.role, {this.superAdmin = false});
  final UserRole role;
  final bool superAdmin;
  @override
  Future<Profile?> fetchMe() async => Profile(
    id: 'u1',
    fullName: 'Chadrack Tambwe',
    role: role,
    email: 'chef@rtc.ml',
    isSuperAdmin: superAdmin,
  );
  @override
  Future<Map<String, String>> fetchNames() async => {};
}

class FakeTeam implements TeamRepository {
  FakeTeam() {
    members = [
      const TeamMember(
        id: 'u1',
        fullName: 'Chadrack Tambwe',
        email: 'chef@rtc.ml',
        role: UserRole.admin,
        active: true,
        isSuperAdmin: true,
      ),
      const TeamMember(
        id: 'u2',
        fullName: 'Awa Traoré',
        email: 'awa@rtc.ml',
        role: UserRole.journalist,
        active: true,
      ),
      const TeamMember(
        id: 'u3',
        fullName: 'Moussa Keita',
        email: 'moussa@rtc.ml',
        role: UserRole.technician,
        active: false,
      ),
    ];
  }
  late List<TeamMember> members;
  final calls = <String>[];
  TeamException? failWith;

  @override
  Future<List<TeamMember>> fetch() async => List.of(members);

  @override
  Future<void> setRole(String id, UserRole role) async {
    if (failWith != null) throw failWith!;
    calls.add('role:$id:${role.name}');
    members = [
      for (final m in members)
        m.id == id
            ? TeamMember(
                id: m.id,
                fullName: m.fullName,
                email: m.email,
                role: role,
                active: m.active,
                isSuperAdmin: m.isSuperAdmin,
              )
            : m,
    ];
  }

  @override
  Future<CreatedMember> create({
    required String email,
    required String fullName,
    required UserRole role,
  }) async {
    if (failWith != null) throw failWith!;
    calls.add('create:$email:$fullName:${role.name}');
    members = [
      ...members,
      TeamMember(
        id: 'n',
        fullName: fullName,
        email: email,
        role: role,
        active: true,
      ),
    ];
    return CreatedMember(
      id: 'n',
      email: email,
      tempPassword: 'Abc123def456ghij',
    );
  }

  @override
  Future<void> setActive(String id, bool active) async {
    if (failWith != null) throw failWith!;
    calls.add('active:$id:$active');
    members = [
      for (final m in members)
        m.id == id
            ? TeamMember(
                id: m.id,
                fullName: m.fullName,
                email: m.email,
                role: m.role,
                active: active,
                isSuperAdmin: m.isSuperAdmin,
              )
            : m,
    ];
  }
}

Future<FakeTeam> pump(
  WidgetTester tester, {
  UserRole role = UserRole.admin,
  bool superAdmin = true,
}) async {
  await initializeDateFormatting('fr');
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final team = FakeTeam();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(TestAuth()),
        profileRepositoryProvider.overrideWithValue(
          TestProfiles(role, superAdmin: superAdmin),
        ),
        teamRepositoryProvider.overrideWithValue(team),
      ],
      child: const RadioFlowApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Mon compte'));
  await tester.pumpAndSettle();
  return team;
}

Future<void> openTeam(WidgetTester tester) async {
  await tester.tap(find.text('Gérer l’équipe'));
  await tester.pumpAndSettle();
}

void main() {
  test('erreurs de connexion : compte désactivé', () {
    expect(
      authErrorMessage(
        const AuthException('User is banned', code: 'user_banned'),
      ),
      contains('désactivé'),
    );
  });

  testWidgets('un journaliste ne voit pas l’entrée « Gérer l’équipe »', (
    tester,
  ) async {
    await pump(tester, role: UserRole.journalist, superAdmin: false);
    expect(find.text('Gérer l’équipe'), findsNothing);
  });

  testWidgets('un rédacteur en chef ordinaire ne gère pas l’équipe', (
    tester,
  ) async {
    await pump(tester, role: UserRole.admin, superAdmin: false);
    expect(find.text('Gérer l’équipe'), findsNothing);
    expect(find.text('Rédacteur en chef'), findsOneWidget);
  });

  testWidgets('le super administrateur est identifié comme tel', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Super administrateur'), findsOneWidget);
    expect(find.text('Gérer l’équipe'), findsOneWidget);
  });

  testWidgets('accès direct à l’écran Équipe sans être super administrateur', (
    tester,
  ) async {
    await pump(tester, role: UserRole.admin, superAdmin: false);
    final context = tester.element(find.text('Mon compte').first);
    GoRouter.of(context).push('/team');
    await tester.pumpAndSettle();
    expect(find.text('Réservé au super administrateur.'), findsOneWidget);
    expect(find.text('Ajouter un membre'), findsNothing);
  });

  testWidgets('liste des membres : rôles, « vous », comptes désactivés', (
    tester,
  ) async {
    await pump(tester);
    await openTeam(tester);
    expect(find.text('Chadrack Tambwe (vous)'), findsOneWidget);
    expect(find.text('Awa Traoré'), findsOneWidget);
    expect(find.text('Super administrateur'), findsOneWidget);
    expect(find.byTooltip('Actions pour Chadrack Tambwe'), findsNothing);
    expect(find.text('Journaliste'), findsOneWidget);
    expect(find.text('Désactivé'), findsOneWidget);
  });

  testWidgets('changer le rôle d’un membre', (tester) async {
    final team = await pump(tester);
    await openTeam(tester);
    await tester.tap(find.byTooltip('Actions pour Awa Traoré'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Technicien / Présentateur').last);
    await tester.pumpAndSettle();
    expect(team.calls, ['role:u2:technician']);
    expect(
      find.text('Technicien / Présentateur'),
      findsNWidgets(2),
    ); // Awa et Moussa
  });

  testWidgets(
    'désactiver un membre demande confirmation; le super administrateur est intouchable',
    (tester) async {
      final team = await pump(tester);
      await openTeam(tester);

      // Le super administrateur n'a aucune action : ni désactivation ni changement de rôle.
      expect(find.byTooltip('Actions pour Chadrack Tambwe'), findsNothing);

      await tester.tap(find.byTooltip('Actions pour Awa Traoré'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Désactiver le compte'));
      await tester.pumpAndSettle();
      expect(find.text('Désactiver Awa Traoré ?'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(team.calls, isEmpty);

      await tester.tap(find.byTooltip('Actions pour Awa Traoré'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Désactiver le compte'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Désactiver'));
      await tester.pumpAndSettle();
      expect(team.calls, ['active:u2:false']);
      expect(find.text('Désactivé'), findsNWidgets(2));
    },
  );

  testWidgets('réactiver un compte désactivé', (tester) async {
    final team = await pump(tester);
    await openTeam(tester);
    await tester.tap(find.byTooltip('Actions pour Moussa Keita'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Réactiver le compte'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Réactiver'));
    await tester.pumpAndSettle();
    expect(team.calls, ['active:u3:true']);
    expect(find.text('Désactivé'), findsNothing);
  });

  testWidgets('erreur du serveur affichée (changement de rôle refusé)', (
    tester,
  ) async {
    final team = await pump(tester);
    team.failWith = const TeamException(
      'Seul le super administrateur peut modifier un rôle',
    );
    await openTeam(tester);
    await tester.tap(find.byTooltip('Actions pour Awa Traoré'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Technicien / Présentateur').last);
    await tester.pumpAndSettle();
    expect(
      find.text('Seul le super administrateur peut modifier un rôle'),
      findsOneWidget,
    );
  });

  testWidgets(
    'ajouter un membre : validation, création, mot de passe affiché une fois et copiable',
    (tester) async {
      final team = await pump(tester);
      final clipboard = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await openTeam(tester);
      await tester.tap(find.text('Ajouter un membre'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Créer le compte'));
      await tester.pumpAndSettle();
      expect(find.text('Saisissez le nom complet.'), findsOneWidget);
      expect(find.text('Email invalide.'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), 'Fatou Diarra');
      await tester.enterText(find.byType(TextFormField).at(1), 'fatou@rtc.ml');
      await tester.tap(find.text('Créer le compte'));
      await tester.pumpAndSettle();

      expect(team.calls, ['create:fatou@rtc.ml:Fatou Diarra:journalist']);
      expect(find.text('Compte créé'), findsOneWidget);
      expect(find.text('Abc123def456ghij'), findsOneWidget);

      await tester.tap(find.text('Copier'));
      await tester.pumpAndSettle();
      expect(clipboard.single, contains('Abc123def456ghij'));
      expect(clipboard.single, contains('fatou@rtc.ml'));
      expect(find.text('Copié dans le presse-papiers'), findsOneWidget);

      await tester.tap(find.text('Terminé'));
      await tester.pumpAndSettle();
      expect(find.text('Abc123def456ghij'), findsNothing); // n'est plus affiché
      expect(
        find.text('Fatou Diarra'),
        findsOneWidget,
      ); // la liste est rafraîchie
    },
  );

  testWidgets(
    'création refusée (email déjà utilisé) : message dans le formulaire',
    (tester) async {
      final team = await pump(tester);
      team.failWith = const TeamException(
        'Un compte existe déjà avec cet email.',
      );
      await openTeam(tester);
      await tester.tap(find.text('Ajouter un membre'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Awa Traoré');
      await tester.enterText(find.byType(TextFormField).at(1), 'awa@rtc.ml');
      await tester.tap(find.text('Créer le compte'));
      await tester.pumpAndSettle();
      expect(
        find.text('Un compte existe déjà avec cet email.'),
        findsOneWidget,
      );
      expect(find.text('Compte créé'), findsNothing);
    },
  );
}
