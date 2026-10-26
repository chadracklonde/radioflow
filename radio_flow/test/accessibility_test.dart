import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:radio_flow/core/router/app_router.dart';
import 'package:radio_flow/core/theme/app_colors.dart';
import 'package:radio_flow/core/theme/app_theme.dart';
import 'package:radio_flow/core/utils/file_saver.dart';
import 'package:radio_flow/features/auth/data/auth_repository.dart';
import 'package:radio_flow/features/auth/data/profile_repository.dart';
import 'package:radio_flow/features/conductor/data/conductor_repository.dart';
import 'package:radio_flow/features/dashboard/data/dashboard_repository.dart';
import 'package:radio_flow/features/forum/data/forum_repository.dart';
import 'package:radio_flow/features/sound_space/data/sound_repository.dart';
import 'package:radio_flow/features/tasks/data/tasks_repository.dart';
import 'package:radio_flow/features/team/data/team_repository.dart';
import 'package:radio_flow/features/threads/data/thread_repository.dart';

import 'conductor_test.dart' as ct;
import 'forum_test.dart' as ft;
import 'tasks_dashboard_test.dart' as td;
import 'team_test.dart' as tt;
import 'widget_test.dart' as wt;

double _lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final l1 = _lum(a), l2 = _lum(b);
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

class _App extends ConsumerWidget {
  const _App(this.theme, this.mode);
  final ThemeData theme;
  final ThemeMode mode;
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: mode,
    routerConfig: ref.watch(routerProvider),
  );
}

Future<void> pumpApp(
  WidgetTester tester, {
  required Size size,
  required ThemeMode mode,
  bool signedIn = true,
  double textScale = 1,
}) async {
  await initializeDateFormatting('fr');
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  final auth = signedIn ? ft.SignedInAuth() : wt.FakeAuth();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        forumRepositoryProvider.overrideWithValue(ft.FakeForum()),
        conductorRepositoryProvider.overrideWithValue(
          ct.FakeConductors(
            conductors: [ct.Conductor0.today()],
            lines: ct.linesForTest,
          ),
        ),
        threadRepositoryProvider.overrideWithValue(ct.FakeThreads()),
        teamRepositoryProvider.overrideWithValue(tt.FakeTeam()),
        profileRepositoryProvider.overrideWithValue(
          tt.TestProfiles(UserRole.admin, superAdmin: true),
        ),
        tasksRepositoryProvider.overrideWithValue(
          td.FakeTasks(td.sampleTasks()),
        ),
        dashboardRepositoryProvider.overrideWithValue(td.FakeDashboard()),
        soundRepositoryProvider.overrideWithValue(td.FakeSound()),
        fileSaverProvider.overrideWithValue(td.FakeSaver()),
      ],
      child: _App(AppTheme.dark, mode),
    ),
  );
  await tester.pumpAndSettle();
}

/// Fait défiler la liste du Forum (le bouton d'une carte basse est d'abord sous « Proposer un sujet »
/// ou sous la barre de navigation), puis ouvre la première discussion de sujet validé.
Future<void> openFirstDiscussion(WidgetTester tester) async {
  final button = find.text('Ouvrir la discussion');
  await tester.scrollUntilVisible(
    button,
    150,
    scrollable: find.byType(Scrollable).last,
  );
  // encore un peu : sinon le bouton reste sous « Proposer un sujet »
  await tester.drag(find.byType(ListView).last, const Offset(0, -120));
  await tester.pumpAndSettle();
  await tester.tap(button.first);
  await tester.pumpAndSettle();
}

// Les sections à contrôler : libellé de l'onglet.
const tabs = ['Forum', 'Conducteur', 'Espace Son', 'Tâches', 'Tableau de bord'];

void main() {
  group('contraste des jetons (WCAG)', () {
    for (final entry in {
      'sombre': AppColors.dark,
      'clair': AppColors.light,
    }.entries) {
      final c = entry.value;
      test('thème ${entry.key} : texte >= 4,5:1', () {
        for (final surface in {
          'fond': c.background,
          'carte': c.card,
          'discret': c.muted,
        }.entries) {
          expect(
            contrast(c.foreground, surface.value),
            greaterThanOrEqualTo(4.5),
            reason: 'texte sur ${surface.key}',
          );
          expect(
            contrast(c.mutedForeground, surface.value),
            greaterThanOrEqualTo(4.5),
            reason: 'texte secondaire sur ${surface.key}',
          );
          expect(
            contrast(c.danger, surface.value),
            greaterThanOrEqualTo(4.5),
            reason: 'danger sur ${surface.key}',
          );
          expect(
            contrast(c.warning, surface.value),
            greaterThanOrEqualTo(4.5),
            reason: 'alerte sur ${surface.key}',
          );
          expect(
            contrast(c.success, surface.value),
            greaterThanOrEqualTo(4.5),
            reason: 'succès sur ${surface.key}',
          );
        }
        expect(
          contrast(c.onSuccess, c.success),
          greaterThanOrEqualTo(4.5),
          reason: 'texte des boutons',
        );
      });
      test('thème ${entry.key} : contours de champs et icônes >= 3:1', () {
        expect(
          contrast(c.border, c.muted),
          greaterThanOrEqualTo(3),
          reason: 'contour des champs',
        );
        expect(contrast(c.border, c.background), greaterThanOrEqualTo(3));
        expect(contrast(c.mutedForeground, c.card), greaterThanOrEqualTo(3));
      });
    }
  });

  for (final mode in [ThemeMode.dark, ThemeMode.light]) {
    final name = mode == ThemeMode.dark ? 'sombre' : 'clair';

    testWidgets(
      'connexion, thème $name : zones tactiles, libellés, contraste',
      (tester) async {
        await pumpApp(
          tester,
          size: const Size(375, 700),
          mode: mode,
          signedIn: false,
        );
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      },
    );

    for (final tab in tabs) {
      testWidgets('$tab, thème $name, 375 px : accessibilité', (tester) async {
        await pumpApp(tester, size: const Size(375, 700), mode: mode);
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      });
    }
  }

  for (final mode in [ThemeMode.dark, ThemeMode.light]) {
    testWidgets(
      'Mon compte, thème ${mode == ThemeMode.dark ? 'sombre' : 'clair'} : accessibilité',
      (tester) async {
        await pumpApp(tester, size: const Size(375, 700), mode: mode);
        await tester.tap(find.byTooltip('Mon compte'));
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      },
    );
  }

  testWidgets(
    'Mon compte : texte 2x, paysage et grand écran sans débordement',
    (tester) async {
      for (final (size, scale) in [
        (const Size(375, 700), 2.0),
        (const Size(667, 375), 1.0),
        (const Size(1440, 900), 1.0),
      ]) {
        await pumpApp(
          tester,
          size: size,
          mode: ThemeMode.dark,
          textScale: scale,
        );
        await tester.tap(find.byTooltip('Mon compte'));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '${size.width}px x$scale',
        );
        // Démonte avant le format suivant : sinon le routeur garde l'écran précédent.
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  for (final mode in [ThemeMode.dark, ThemeMode.light]) {
    testWidgets(
      'Équipe, thème ${mode == ThemeMode.dark ? 'sombre' : 'clair'} : accessibilité',
      (tester) async {
        await pumpApp(tester, size: const Size(375, 700), mode: mode);
        await tester.tap(find.byTooltip('Mon compte'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Gérer l\u2019équipe'));
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      },
    );
  }

  testWidgets('Équipe : texte 2x et paysage sans débordement', (tester) async {
    for (final (size, scale) in [
      (const Size(375, 700), 2.0),
      (const Size(667, 375), 1.0),
    ]) {
      await pumpApp(tester, size: size, mode: ThemeMode.dark, textScale: scale);
      await tester.tap(find.byTooltip('Mon compte'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gérer l\u2019équipe'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '${size.width}px x$scale');
      await tester.pumpWidget(const SizedBox());
    }
  });

  for (final mode in [ThemeMode.dark, ThemeMode.light]) {
    testWidgets(
      'Discussion d’un sujet validé, thème ${mode == ThemeMode.dark ? 'sombre' : 'clair'} : accessibilité',
      (tester) async {
        await pumpApp(tester, size: const Size(375, 700), mode: mode);
        await openFirstDiscussion(tester);
        await tester.pumpAndSettle();
        expect(find.byTooltip('Envoyer'), findsOneWidget);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      },
    );
  }

  testWidgets('Discussion d’un sujet : texte 2x et paysage sans débordement', (
    tester,
  ) async {
    for (final (size, scale) in [
      (const Size(375, 700), 2.0),
      (const Size(667, 375), 1.0),
    ]) {
      await pumpApp(tester, size: size, mode: ThemeMode.dark, textScale: scale);
      await openFirstDiscussion(tester);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '${size.width}px x$scale');
      await tester.pumpWidget(const SizedBox());
    }
  });

  group('tailles de texte et orientation', () {
    for (final tab in tabs) {
      testWidgets('$tab : texte agrandi 2x sans débordement (375 px)', (
        tester,
      ) async {
        await pumpApp(
          tester,
          size: const Size(375, 700),
          mode: ThemeMode.dark,
          textScale: 2,
        );
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
      testWidgets('$tab : paysage téléphone (667x375) sans débordement', (
        tester,
      ) async {
        await pumpApp(tester, size: const Size(667, 375), mode: ThemeMode.dark);
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('tablette (820x1180) et grand écran (1440x900)', (
      tester,
    ) async {
      for (final size in const [Size(820, 1180), Size(1440, 900)]) {
        await pumpApp(tester, size: size, mode: ThemeMode.dark);
        for (final tab in tabs) {
          await tester.tap(find.text(tab).last);
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$tab à ${size.width}px',
          );
        }
      }
    });
  });
}
