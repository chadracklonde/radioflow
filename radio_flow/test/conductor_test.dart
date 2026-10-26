import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'dart:typed_data';

import 'package:radio_flow/app.dart';
import 'package:radio_flow/core/utils/file_saver.dart';
import 'package:radio_flow/features/auth/data/auth_repository.dart';
import 'package:radio_flow/features/auth/data/profile_repository.dart';
import 'package:radio_flow/features/conductor/data/conductor_repository.dart';
import 'package:radio_flow/features/conductor/domain/conductor_models.dart';
import 'package:radio_flow/features/threads/data/thread_repository.dart';
import 'package:radio_flow/features/threads/domain/thread_message.dart';

class SignedIn implements AuthRepository {
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

class Profiles implements ProfileRepository {
  Profiles(this.role);
  final UserRole role;
  @override
  Future<Profile?> fetchMe() async =>
      Profile(id: 'u1', fullName: 'Awa Traoré', role: role);
  @override
  Future<Map<String, String>> fetchNames() async => {'u1': 'Awa Traoré'};
}

class FakeConductors implements ConductorRepository {
  FakeConductors({
    this.conductors = const [],
    this.lines = const [],
    this.slots = const [],
  });
  List<BroadcastSlot> slots;
  List<Conductor> conductors;
  List<ConductorLine> lines;
  final _changes = StreamController<void>.broadcast();
  final calls = <String>[];

  Stream<T> _live<T>(T Function() read) async* {
    yield read();
    await for (final _ in _changes.stream) {
      yield read();
    }
  }

  @override
  Stream<List<Conductor>> watchConductors(String isoDate) =>
      _live(() => List.of(conductors));
  @override
  Stream<List<ConductorLine>> watchLines(String conductorId) =>
      _live(() => List.of(lines));
  @override
  Future<List<BroadcastSlot>> fetchSlots() async => List.of(slots);

  @override
  Future<int> generate(DateTime date) async {
    calls.add('generate');
    conductors = [
      Conductor(
        id: 'c1',
        title: 'Journal de 12h',
        broadcastDate: date,
        status: ConductorStatus.open,
        broadcastTime: '12:00',
      ),
    ];
    _changes.add(null);
    return 1;
  }

  @override
  Future<void> addSlot({
    required String title,
    required String time,
    List<int> weekdays = BroadcastSlot.allWeekdays,
    int? durationSeconds,
  }) async {
    calls.add(
      'addSlot:$title:$time:${weekdays.join()}:${durationSeconds ?? '-'}',
    );
    slots = [
      ...slots,
      BroadcastSlot(
        id: 's${slots.length + 1}',
        title: title,
        time: time,
        active: true,
        weekdays: weekdays,
      ),
    ];
  }

  @override
  Future<void> setLineScript(String lineId, String? text) async {
    calls.add('script:$lineId:${text ?? ''}');
    lines = [
      for (final l in lines)
        if (l.id == lineId)
          ConductorLine(
            id: l.id,
            conductorId: l.conductorId,
            position: l.position,
            itemType: l.itemType,
            title: l.title,
            status: l.status,
            plannedDuration: l.plannedDuration,
            script: (text == null || text.isEmpty) ? null : text,
          )
        else
          l,
    ];
    _changes.add(null);
  }

  @override
  Future<int> saveAsTemplate(String conductorId) async {
    calls.add('template:$conductorId');
    return lines.length;
  }

  List<HistoryEntry> history = const [];
  @override
  Future<List<HistoryEntry>> fetchHistory(String conductorId) async => history;

  @override
  Future<void> removeSlot(String id) async {
    calls.add('removeSlot:$id');
    slots = slots.where((s) => s.id != id).toList();
  }

  @override
  Future<String> addLine({
    String? id,
    required String conductorId,
    required String title,
    required LineItemType type,
    int? plannedDuration,
  }) async {
    calls.add('add:$title:${plannedDuration ?? '-'}');
    final newId = 'l${lines.length + 1}';
    lines = [
      ...lines,
      ConductorLine(
        id: newId,
        conductorId: conductorId,
        position: lines.length + 1,
        itemType: type,
        title: title,
        status: LineStatus.planned,
        plannedDuration: plannedDuration,
      ),
    ];
    _changes.add(null);
    return newId;
  }

  @override
  Future<void> swapLines(String a, String b) async => calls.add('swap:$a:$b');
  @override
  Future<void> setConductorStatus(String id, ConductorStatus status) async =>
      calls.add('cstatus:${status.name}');
  @override
  Future<void> setLineStatus(String id, LineStatus status) async =>
      calls.add('lstatus:${status.dbValue}');
}

class _Saver implements FileSaver {
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
      userId: 'u1',
      createdAt: DateTime(2026, 9, 9, 9),
      content: 'Le son arrive',
    ),
    ThreadMessage(
      id: 'm2',
      userId: 'u1',
      createdAt: DateTime(2026, 9, 9, 10),
      audioUrl: 'c1/01_Marche_2026-09-09.mp3',
      audioName: 'Marche.mp3',
      audioDuration: 95,
    ),
  ]);
  @override
  Future<void> sendText({
    String? id,
    required String threadId,
    required String userId,
    required String text,
  }) async => sent.add(text);
}

final _today = DateTime.now();

Conductor _conductor(ConductorStatus s) => Conductor(
  id: 'c1',
  title: 'Journal de 12h',
  broadcastDate: DateTime(_today.year, _today.month, _today.day),
  status: s,
  broadcastTime: '12:00',
);

const linesForTest = _lines;

const _lines = [
  ConductorLine(
    id: 'l1',
    conductorId: 'c1',
    position: 1,
    itemType: LineItemType.jingle,
    title: 'Générique',
    status: LineStatus.ready,
    plannedDuration: 15,
  ),
  ConductorLine(
    id: 'l2',
    conductorId: 'c1',
    position: 2,
    itemType: LineItemType.reportage,
    title: 'Marché de Bamako',
    status: LineStatus.planned,
    plannedDuration: 150,
  ),
];

Future<(FakeConductors, FakeThreads)> pump(
  WidgetTester tester,
  UserRole role, {
  FakeConductors? conductors,
  FileSaver? saver,
}) async {
  await initializeDateFormatting('fr');
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = conductors ?? FakeConductors();
  final threads = FakeThreads();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(SignedIn()),
        profileRepositoryProvider.overrideWithValue(Profiles(role)),
        conductorRepositoryProvider.overrideWithValue(repo),
        threadRepositoryProvider.overrideWithValue(threads),
        if (saver != null) fileSaverProvider.overrideWithValue(saver),
      ],
      child: const RadioFlowApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Conducteur').last);
  await tester.pumpAndSettle();
  return (repo, threads);
}

void main() {
  testWidgets('conducteur : export PDF et chronométrage affiché', (
    tester,
  ) async {
    final saver = _Saver();
    final repo = FakeConductors(
      conductors: [_conductor(ConductorStatus.open)],
      lines: _lines,
    );
    await pump(tester, UserRole.journalist, conductors: repo, saver: saver);
    await tester.tap(find.text('Journal de 12h'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Prévu '), findsOneWidget);
    expect(find.textContaining('Estimé '), findsOneWidget);
    await tester.tap(find.byTooltip('Exporter en PDF'));
    await tester.pumpAndSettle();
    final name = saver.saved.keys.single;
    expect(name, startsWith('RadioFlow_Conducteur_'));
    expect(name, endsWith('.pdf'));
    expect(String.fromCharCodes(saver.saved[name]!.take(4)), '%PDF');
  });

  test(
    'chronométrage : le son remplace la durée prévue, abandonnées ignorées',
    () {
      const lines = [
        ConductorLine(
          id: 'a',
          conductorId: 'c',
          position: 1,
          itemType: LineItemType.jingle,
          title: 'A',
          status: LineStatus.ready,
          plannedDuration: 60,
        ),
        ConductorLine(
          id: 'b',
          conductorId: 'c',
          position: 2,
          itemType: LineItemType.reportage,
          title: 'B',
          status: LineStatus.planned,
          plannedDuration: 120,
        ),
        ConductorLine(
          id: 'c',
          conductorId: 'c',
          position: 3,
          itemType: LineItemType.brief,
          title: 'C',
          status: LineStatus.dropped,
          plannedDuration: 500,
        ),
      ];
      final t = ConductorTiming.compute(lines, {'b': 150, 'c': 99});
      expect(t.planned, 180);
      expect(t.estimated, 210);
      expect(t.withSound, 1);
      expect(t.counted, 2);
    },
  );

  test('durées : mm:ss et secondes', () {
    expect(parseDuration('2:30'), 150);
    expect(parseDuration('150'), 150);
    expect(parseDuration(''), isNull);
    expect(parseDuration('2:75'), isNull);
    expect(parseDuration('abc'), isNull);
    expect(formatDuration(95), '1:35');
    expect(formatDuration(15), '0:15');
  });

  const daily = BroadcastSlot(
    id: 's1',
    title: 'Journal de 12h',
    time: '12:00',
    active: true,
  );

  testWidgets('admin : génère les conducteurs du jour depuis la grille', (
    tester,
  ) async {
    final (repo, _) = await pump(
      tester,
      UserRole.admin,
      conductors: FakeConductors(slots: [daily]),
    );
    expect(find.text('Aucun conducteur ce jour-là.'), findsOneWidget);
    await tester.tap(find.text('Générer d’après la grille'));
    await tester.pumpAndSettle();
    expect(repo.calls, ['generate']);
    expect(find.text('Journal de 12h'), findsOneWidget);
    expect(find.text('12:00'), findsOneWidget);
    expect(find.text('1 conducteur créé.'), findsOneWidget);
  });

  testWidgets('admin : grille vide -> explication et accès à la grille', (
    tester,
  ) async {
    final (repo, _) = await pump(tester, UserRole.admin);
    expect(
      find.textContaining('La grille de la station est vide'),
      findsOneWidget,
    );
    expect(find.text('Générer d’après la grille'), findsNothing);
    await tester.tap(find.text('Configurer la grille'));
    await tester.pumpAndSettle();
    expect(find.text('Grille de la station'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Flash');
    await tester.enterText(find.byType(TextField).at(1), '30');
    await tester.tap(find.text('Ven'));
    await tester.pump();
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();
    expect(repo.calls, ['addSlot:Flash:07:00:123467:1800']);
    expect(find.text('Flash'), findsOneWidget);

    await tester.tap(find.byTooltip('Supprimer Flash'));
    await tester.pumpAndSettle();
    expect(repo.calls.last, 'removeSlot:s1');
    expect(find.text('Flash'), findsNothing);
  });

  testWidgets('admin : aucun créneau ce jour de la semaine -> message', (
    tester,
  ) async {
    final other = [
      for (var d = 1; d <= 7; d++)
        if (d != DateTime.now().weekday) d,
    ];
    await pump(
      tester,
      UserRole.admin,
      conductors: FakeConductors(
        slots: [
          BroadcastSlot(
            id: 's1',
            title: 'Flash',
            time: '07:00',
            active: true,
            weekdays: other,
          ),
        ],
      ),
    );
    expect(
      find.textContaining('Aucun créneau de la grille n’est prévu'),
      findsOneWidget,
    );
    expect(find.text('Configurer la grille'), findsOneWidget);
  });

  testWidgets('admin : l’icône génère les conducteurs manquants', (
    tester,
  ) async {
    final (repo, _) = await pump(
      tester,
      UserRole.admin,
      conductors: FakeConductors(
        conductors: [_conductor(ConductorStatus.open)],
        slots: [daily],
      ),
    );
    await tester.tap(find.byTooltip('Générer les conducteurs manquants'));
    await tester.pumpAndSettle();
    expect(repo.calls, ['generate']);
  });

  testWidgets('journaliste : pas de bouton de génération', (tester) async {
    await pump(tester, UserRole.journalist);
    expect(find.text('Aucun conducteur ce jour-là.'), findsOneWidget);
    expect(find.text('Générer d’après la grille'), findsNothing);
    expect(find.byTooltip('Générer les conducteurs manquants'), findsNothing);
  });

  testWidgets('admin : lignes, réordonnancement, ajout, verrouillage', (
    tester,
  ) async {
    final repo = FakeConductors(
      conductors: [_conductor(ConductorStatus.open)],
      lines: _lines,
    );
    await pump(tester, UserRole.admin, conductors: repo);
    await tester.tap(find.text('Journal de 12h'));
    await tester.pumpAndSettle();

    expect(find.text('Générique'), findsOneWidget);
    expect(find.text('Marché de Bamako'), findsOneWidget);
    expect(find.text('2:30'), findsOneWidget);

    await tester.tap(find.byTooltip('Descendre').first);
    await tester.pumpAndSettle();
    expect(repo.calls, contains('swap:l1:l2'));

    await tester.tap(find.text('Ajouter une ligne'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();
    expect(find.text('Donnez un titre à la ligne.'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'Interview ministre',
    );
    await tester.enterText(find.byType(TextFormField).at(1), '3:00');
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();
    expect(repo.calls, contains('add:Interview ministre:180'));
    expect(find.text('Interview ministre'), findsOneWidget);

    await tester.tap(find.byTooltip('Statut du conducteur'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verrouillé'));
    await tester.pumpAndSettle();
    expect(repo.calls, contains('cstatus:locked'));
  });

  testWidgets(
    'conducteur verrouillé : bandeau, pas de contrôles pour un journaliste',
    (tester) async {
      final repo = FakeConductors(
        conductors: [_conductor(ConductorStatus.locked)],
        lines: _lines,
      );
      await pump(tester, UserRole.journalist, conductors: repo);
      await tester.tap(find.text('Journal de 12h'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('plus d’upload audio possible'),
        findsOneWidget,
      );
      expect(find.text('Ajouter une ligne'), findsNothing);
      expect(find.byTooltip('Descendre'), findsNothing);
    },
  );

  Future<FakeConductors> openLine(
    WidgetTester tester,
    UserRole role, {
    ConductorStatus status = ConductorStatus.open,
    List<ConductorLine>? lines,
  }) async {
    final repo = FakeConductors(
      conductors: [_conductor(status)],
      lines: lines ?? _lines,
    );
    await pump(tester, role, conductors: repo);
    await tester.tap(find.text('Journal de 12h'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marché de Bamako'));
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('texte à l’antenne : un journaliste l’écrit puis le modifie', (
    tester,
  ) async {
    final repo = await openLine(tester, UserRole.journalist);
    expect(find.text('Aucun texte pour cette ligne.'), findsOneWidget);
    await tester.tap(find.text('Écrire'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Bonjour Bamako');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(repo.calls, ['script:l2:Bonjour Bamako']);
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      'Bonjour Bamako',
    );
    expect(find.text('Modifier'), findsOneWidget);
  });

  testWidgets('texte à l’antenne : lecture seule pour un technicien', (
    tester,
  ) async {
    await openLine(tester, UserRole.technician);
    expect(find.text('Texte à lire à l’antenne'), findsOneWidget);
    expect(find.text('Écrire'), findsNothing);
  });

  testWidgets(
    'texte à l’antenne : verrouillé pour un journaliste, libre pour l’admin',
    (tester) async {
      await openLine(
        tester,
        UserRole.journalist,
        status: ConductorStatus.locked,
      );
      expect(find.text('Écrire'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await openLine(tester, UserRole.admin, status: ConductorStatus.locked);
      expect(find.text('Écrire'), findsOneWidget);
    },
  );

  testWidgets('historique des modifications', (tester) async {
    final repo =
        FakeConductors(
            conductors: [_conductor(ConductorStatus.open)],
            lines: _lines,
          )
          ..history = [
            HistoryEntry(
              id: 2,
              summary: 'Texte de « Marché de Bamako » modifié',
              createdAt: DateTime(2026, 9, 9, 10, 30),
              userId: 'u1',
            ),
          ];
    await pump(tester, UserRole.journalist, conductors: repo);
    await tester.tap(find.text('Journal de 12h'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Historique des modifications'));
    await tester.pumpAndSettle();
    expect(find.text('Texte de « Marché de Bamako » modifié'), findsOneWidget);
    expect(find.textContaining('Awa Traoré · 09/09 10:30'), findsOneWidget);
  });

  testWidgets(
    'modèle : enregistré par l’admin pour un conducteur issu de la grille',
    (tester) async {
      final withSlot = Conductor(
        id: 'c1',
        title: 'Journal de 12h',
        broadcastDate: DateTime(_today.year, _today.month, _today.day),
        status: ConductorStatus.open,
        broadcastTime: '12:00',
        slotId: 's1',
        targetDuration: 120,
      );
      final repo = FakeConductors(conductors: [withSlot], lines: _lines);
      await pump(tester, UserRole.admin, conductors: repo);
      await tester.tap(find.text('Journal de 12h'));
      await tester.pumpAndSettle();
      // durée prévue 2:45 pour une cible de 2:00
      expect(find.text('Cible 2:00'), findsOneWidget);
      expect(find.text('Dépassement de 0:45'), findsOneWidget);
      await tester.tap(find.byTooltip('Enregistrer comme modèle du créneau'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(repo.calls, ['template:c1']);
      expect(find.text('Modèle enregistré : 2 lignes.'), findsOneWidget);
    },
  );

  testWidgets('modèle : pas de bouton pour un journaliste', (tester) async {
    final repo = FakeConductors(
      conductors: [
        Conductor(
          id: 'c1',
          title: 'Journal de 12h',
          broadcastDate: DateTime(_today.year, _today.month, _today.day),
          status: ConductorStatus.open,
          slotId: 's1',
        ),
      ],
      lines: _lines,
    );
    await pump(tester, UserRole.journalist, conductors: repo);
    await tester.tap(find.text('Journal de 12h'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Enregistrer comme modèle du créneau'), findsNothing);
  });

  testWidgets('fil de discussion : messages texte et audio, envoi', (
    tester,
  ) async {
    final repo = FakeConductors(
      conductors: [_conductor(ConductorStatus.open)],
      lines: _lines,
    );
    final (_, threads) = await pump(
      tester,
      UserRole.journalist,
      conductors: repo,
    );
    await tester.tap(find.text('Journal de 12h'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marché de Bamako'));
    await tester.pumpAndSettle();

    expect(find.text('Le son arrive'), findsOneWidget);
    expect(find.text('Marche.mp3'), findsOneWidget);
    expect(find.text('1:35'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Montage terminé');
    await tester.tap(find.byTooltip('Envoyer'));
    await tester.pumpAndSettle();
    expect(threads.sent, ['Montage terminé']);
  });
}

/// Conducteur du jour, ouvert (pour les tests d'accessibilité).
class Conductor0 {
  static Conductor today() => _conductor(ConductorStatus.open);
}
