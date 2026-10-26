import 'dart:async';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:radio_flow/app.dart';
import 'package:radio_flow/core/utils/file_saver.dart';
import 'package:radio_flow/features/auth/data/auth_repository.dart';
import 'package:radio_flow/features/auth/data/profile_repository.dart';
import 'package:radio_flow/features/dashboard/data/dashboard_repository.dart';
import 'package:radio_flow/features/dashboard/data/report_export.dart';
import 'package:radio_flow/features/dashboard/domain/report.dart';
import 'package:radio_flow/features/sound_space/data/sound_repository.dart';
import 'package:radio_flow/features/sound_space/domain/sound_file.dart';
import 'package:radio_flow/features/tasks/data/tasks_repository.dart';
import 'package:radio_flow/features/tasks/domain/task_models.dart';

class FakeAuth implements AuthRepository {
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

class FakeTasks implements TasksRepository {
  FakeTasks(this.items);
  List<TeamTask> items;
  final _ctrl = StreamController<void>.broadcast();
  final calls = <String>[];

  @override
  Stream<List<TeamTask>> watch() async* {
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
    calls.add('add:$userId:$title');
    items = [
      TeamTask(
        id: 'n${items.length}',
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
    calls.add('status:$id:${status.name}');
    items = [
      for (final t in items)
        t.id == id
            ? TeamTask(
                id: t.id,
                userId: t.userId,
                title: t.title,
                status: status,
                dueDate: t.dueDate,
              )
            : t,
    ];
    _ctrl.add(null);
  }

  @override
  Future<void> delete(String id) async {
    calls.add('delete:$id');
    items = items.where((t) => t.id != id).toList();
    _ctrl.add(null);
  }
}

class FakeDashboard implements DashboardRepository {
  final requested = <DateRange>[];
  @override
  Future<List<ProductionRow>> fetchStats(DateRange range) async {
    requested.add(range);
    return const [
      ProductionRow(
        userId: 'u2',
        name: 'Moussa Keita',
        audioCount: 4,
        approvedProposals: 2,
        tasksDone: 3,
        tasksOpen: 1,
      ),
      ProductionRow(
        userId: 'u1',
        name: 'Awa Traoré',
        audioCount: 2,
        approvedProposals: 0,
        tasksDone: 1,
        tasksOpen: 2,
      ),
    ];
  }
}

class FakeSound implements SoundRepository {
  @override
  Stream<void> changes() => const Stream.empty();
  @override
  Future<List<SoundFile>> fetchFiles(String isoDate) async => const [];
  @override
  Future<String> upload({
    required String conductorId,
    required String threadId,
    required String userId,
    required int position,
    required DateTime date,
    required String originalName,
    required Uint8List bytes,
    int? durationSeconds,
  }) async => '';
  @override
  Future<void> deleteSound(SoundFile file) async {}
  @override
  Future<String> signedUrl(String path) async => '';
  @override
  Future<Uint8List> download(String path) async => Uint8List(0);
}

class FakeSaver implements FileSaver {
  final saved = <String, Uint8List>{};
  @override
  Future<bool> save({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    saved[fileName] = bytes;
    return true;
  }
}

final _today = DateTime.now();
final _yesterday = DateTime(
  _today.year,
  _today.month,
  _today.day,
).subtract(const Duration(days: 1));

List<TeamTask> sampleTasks() => [
  TeamTask(
    id: 't1',
    userId: 'u1',
    title: 'Monter le reportage',
    status: TaskStatus.editing,
    dueDate: _yesterday,
  ),
  const TeamTask(
    id: 't2',
    userId: 'u2',
    title: 'Interview du maire',
    status: TaskStatus.reporting,
  ),
  const TeamTask(
    id: 't3',
    userId: 'u2',
    title: 'Brève météo',
    status: TaskStatus.done,
  ),
];

class Env {
  Env(this.tasks, this.dashboard, this.saver);
  final FakeTasks tasks;
  final FakeDashboard dashboard;
  final FakeSaver saver;
}

Future<Env> pump(
  WidgetTester tester,
  String tab, {
  UserRole role = UserRole.journalist,
}) async {
  await initializeDateFormatting('fr');
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final env = Env(FakeTasks(sampleTasks()), FakeDashboard(), FakeSaver());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuth()),
        profileRepositoryProvider.overrideWithValue(FakeProfiles(role)),
        tasksRepositoryProvider.overrideWithValue(env.tasks),
        dashboardRepositoryProvider.overrideWithValue(env.dashboard),
        soundRepositoryProvider.overrideWithValue(FakeSound()),
        fileSaverProvider.overrideWithValue(env.saver),
      ],
      child: const RadioFlowApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(tab).last);
  await tester.pumpAndSettle();
  return env;
}

DashboardReport sampleReport() => DashboardReport(
  range: DateRange(DateTime(2026, 9, 7), DateTime(2026, 9, 13)),
  rows: const [
    ProductionRow(
      userId: 'u2',
      name: 'Moussa Keita',
      audioCount: 4,
      approvedProposals: 2,
      tasksDone: 3,
      tasksOpen: 1,
    ),
    ProductionRow(
      userId: 'u1',
      name: 'Awa Traoré',
      audioCount: 2,
      approvedProposals: 0,
      tasksDone: 1,
      tasksOpen: 2,
    ),
  ],
  openTasks: [
    OpenTaskLine(
      owner: 'Awa Traoré',
      title: 'Monter le reportage',
      status: 'En montage',
      due: DateTime(2026, 9, 10),
    ),
  ],
  generatedAt: DateTime(2026, 9, 9, 8, 30),
);

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  group('périodes', () {
    test('semaine : du lundi au dimanche', () {
      final r = DateRange.week(DateTime(2026, 9, 9)); // mercredi
      expect(r.from, DateTime(2026, 9, 7));
      expect(r.to, DateTime(2026, 9, 13));
      final sunday = DateRange.week(DateTime(2026, 9, 13));
      expect(sunday.from, DateTime(2026, 9, 7));
    });
    test('mois : du 1er au dernier jour', () {
      final r = DateRange.month(DateTime(2026, 2, 10));
      expect(r.from, DateTime(2026, 2, 1));
      expect(r.to, DateTime(2026, 2, 28));
      expect(DateRange.month(DateTime(2026, 12, 5)).to, DateTime(2026, 12, 31));
    });
  });

  group('exports', () {
    test('Excel : classement, total, tâches en cours', () {
      final book = Excel.decodeBytes(buildXlsx(sampleReport()));
      expect(
        book.tables.keys,
        containsAll(['Classement', 'Tâches en cours', 'Période']),
      );
      final rows = book['Classement'].rows
          .map((r) => r.map((c) => c?.value?.toString()).toList())
          .toList();
      expect(rows[0], [
        'Rang',
        'Journaliste',
        'Sons publiés',
        'Sujets validés',
        'Tâches terminées',
        'Tâches en cours',
      ]);
      expect(rows[1], ['1', 'Moussa Keita', '4', '2', '3', '1']);
      expect(rows[2], ['2', 'Awa Traoré', '2', '0', '1', '2']);
      expect(rows[3], ['', 'Total', '6', '2', '4', '1']);
      final tasks = book['Tâches en cours'].rows
          .map((r) => r.map((c) => c?.value?.toString()).toList())
          .toList();
      expect(tasks[1], [
        'Awa Traoré',
        'Monter le reportage',
        'En montage',
        '10/09/2026',
      ]);
    });

    test('PDF : document valide', () async {
      final bytes = await buildPdf(sampleReport());
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(1000));
    });

    test('nom de fichier', () {
      expect(
        exportBaseName(sampleReport()),
        'RadioFlow_Bilan_2026-09-07_2026-09-13',
      );
    });
  });

  testWidgets('Tâches : en cours / terminées, filtre « mes tâches »', (
    tester,
  ) async {
    await pump(tester, 'Tâches');
    expect(find.text('Monter le reportage'), findsOneWidget);
    expect(find.text('Interview du maire'), findsOneWidget);
    expect(find.text('Brève météo'), findsNothing);
    expect(find.textContaining('En retard'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Mes tâches'));
    await tester.pumpAndSettle();
    expect(find.text('Interview du maire'), findsNothing);
    expect(find.text('Monter le reportage'), findsOneWidget);

    await tester.tap(find.text('Terminées'));
    await tester.pumpAndSettle();
    expect(find.text('Aucune tâche terminée.'), findsOneWidget);
  });

  testWidgets(
    'Tâches : création, changement de statut, suppression (les siennes)',
    (tester) async {
      final env = await pump(tester, 'Tâches');
      await tester.tap(find.text('Nouvelle tâche'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Créer'));
      await tester.pumpAndSettle();
      expect(find.text('Décrivez la tâche.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'Préparer le flash');
      await tester.tap(find.text('Créer'));
      await tester.pumpAndSettle();
      expect(env.tasks.calls, ['add:u1:Préparer le flash']);
      expect(find.text('Préparer le flash'), findsOneWidget);

      await tester.tap(find.byTooltip('Changer le statut').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Terminée').last);
      await tester.pumpAndSettle();
      expect(env.tasks.calls.last, startsWith('status:'));
      expect(env.tasks.calls.last, endsWith(':done'));

      await tester.tap(find.byTooltip('Supprimer la tâche').first);
      await tester.pumpAndSettle();
      expect(env.tasks.calls.last, startsWith('delete:'));
    },
  );

  testWidgets('Tâches : un journaliste ne modifie pas la tâche d’un autre', (
    tester,
  ) async {
    await pump(tester, 'Tâches');
    // 2 tâches en cours : une à lui (t1), une à Moussa (t2) -> un seul menu de statut
    expect(find.byTooltip('Changer le statut'), findsOneWidget);
    expect(find.byTooltip('Supprimer la tâche'), findsOneWidget);
  });

  testWidgets('Tâches : l’admin gère toutes les tâches', (tester) async {
    await pump(tester, 'Tâches', role: UserRole.admin);
    expect(find.byTooltip('Changer le statut'), findsNWidgets(2));
  });

  testWidgets('Tableau de bord : indicateurs, classement et tâches en cours', (
    tester,
  ) async {
    final env = await pump(tester, 'Tableau de bord');
    expect(find.text('Classement des productions'), findsOneWidget);
    expect(find.text('4 sons'), findsOneWidget);
    expect(find.text('2 sons'), findsOneWidget);
    expect(env.dashboard.requested.first.from.weekday, DateTime.monday);
    // Moussa (4 sons) est classé devant Awa (2 sons)
    final moussa = tester.getTopLeft(find.text('Moussa Keita').first).dy;
    final awa = tester.getTopLeft(find.text('Awa Traoré').first).dy;
    expect(moussa, lessThan(awa));
    await tester.scrollUntilVisible(
      find.text('Tâches en cours (2)'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Tâches en cours (2)'), findsOneWidget);
    expect(find.text('Monter le reportage'), findsOneWidget);
  });

  testWidgets('Tableau de bord : changement de période', (tester) async {
    final env = await pump(tester, 'Tableau de bord');
    await tester.tap(find.text('Mois'));
    await tester.pumpAndSettle();
    final last = env.dashboard.requested.last;
    expect(last.from.day, 1);
    expect(last.from.month, last.to.month);
  });

  testWidgets('Tableau de bord : export PDF et Excel', (tester) async {
    final env = await pump(tester, 'Tableau de bord');
    await tester.tap(find.text('PDF'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excel'));
    await tester.pumpAndSettle();
    final names = env.saver.saved.keys.toList();
    expect(names.length, 2);
    expect(
      names.any((n) => n.startsWith('RadioFlow_Bilan_') && n.endsWith('.pdf')),
      isTrue,
    );
    expect(names.any((n) => n.endsWith('.xlsx')), isTrue);
    final pdf = env.saver.saved[names.firstWhere((n) => n.endsWith('.pdf'))]!;
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
  });
}
