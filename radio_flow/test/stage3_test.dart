import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:radio_flow/app.dart';
import 'package:radio_flow/core/utils/audio_naming.dart';
import 'package:radio_flow/features/archives/data/archive_repository.dart';
import 'package:radio_flow/features/auth/data/auth_repository.dart';
import 'package:radio_flow/features/auth/data/profile_repository.dart';
import 'package:radio_flow/features/conductor/data/conductor_repository.dart';
import 'package:radio_flow/features/conductor/domain/conductor_models.dart';
import 'package:radio_flow/features/search/data/search_repository.dart';
import 'package:radio_flow/features/sound_space/data/sound_repository.dart';
import 'package:radio_flow/features/sound_space/data/sounds_zip.dart';
import 'package:radio_flow/features/sound_space/domain/sound_file.dart';
import 'package:radio_flow/features/threads/data/thread_repository.dart';

import 'conductor_test.dart' as ct;
import 'sound_space_test.dart' as st;

class FakeSearch implements SearchRepository {
  FakeSearch(this.hits);
  final List<SearchHit> hits;
  final queries = <String>[];
  @override
  Future<List<SearchHit>> search(String query) async {
    queries.add(query);
    return hits;
  }
}

class FakeArchive implements ArchiveRepository {
  FakeArchive({this.past = const [], this.sounds = const []});
  final List<Conductor> past;
  final List<SoundFile> sounds;
  DateTime? askedBefore;
  @override
  Future<List<Conductor>> fetchPast({
    required DateTime before,
    int limit = 300,
  }) async => past;
  @override
  Future<List<SoundFile>> fetchAiredSounds({required DateTime before}) async {
    askedBefore = before;
    return sounds;
  }
}

SoundFile _sound(String id) => SoundFile(
  messageId: id,
  conductorId: 'c0',
  conductorTitle: 'Journal',
  broadcastTime: '12:00',
  lineId: 'l1',
  position: 1,
  lineTitle: 'Titres',
  storagePath: 'c0/01_Titres_2026-01-05.mp3',
  uploadedBy: 'u1',
  uploadedAt: DateTime(2026, 1, 5),
);

Future<void> pumpApp(
  WidgetTester tester, {
  UserRole role = UserRole.admin,
  FakeSearch? search,
  FakeArchive? archive,
  st.FakeSound? sound,
}) async {
  await initializeDateFormatting('fr');
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(ct.SignedIn()),
        profileRepositoryProvider.overrideWithValue(ct.Profiles(role)),
        conductorRepositoryProvider.overrideWithValue(ct.FakeConductors()),
        threadRepositoryProvider.overrideWithValue(ct.FakeThreads()),
        if (search != null) searchRepositoryProvider.overrideWithValue(search),
        if (archive != null)
          archiveRepositoryProvider.overrideWithValue(archive),
        if (sound != null) soundRepositoryProvider.overrideWithValue(sound),
      ],
      child: const RadioFlowApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('renommage : seuls les fichiers dont la position a changé', () {
    final plan = planSoundRenames([
      (
        messageId: 'm1',
        conductorId: 'c1',
        path: 'c1/01_Jingle_2026-09-09.mp3',
        originalName: 'Jingle.mp3',
        position: 2, // la ligne est passée en position 2
        date: DateTime(2026, 9, 9),
      ),
      (
        messageId: 'm2',
        conductorId: 'c1',
        path: 'c1/02_Reportage_Marche_2026-09-09.wav',
        originalName: 'Reportage Marché.wav',
        position: 2, // déjà à jour
        date: DateTime(2026, 9, 9),
      ),
      (
        messageId: 'm3',
        conductorId: 'c1',
        path: 'c1/vieux.mp3',
        originalName: null, // nom d'origine inconnu : on ne touche pas
        position: 3,
        date: DateTime(2026, 9, 9),
      ),
    ]);
    expect(plan, hasLength(1));
    expect(plan.single.messageId, 'm1');
    expect(plan.single.to, 'c1/02_Jingle_2026-09-09.mp3');
  });

  test('renommage : deux lignes qui échangent leurs positions', () {
    final plan = planSoundRenames([
      (
        messageId: 'a',
        conductorId: 'c',
        path: 'c/01_Son_2026-09-09.mp3',
        originalName: 'Son.mp3',
        position: 2,
        date: DateTime(2026, 9, 9),
      ),
      (
        messageId: 'b',
        conductorId: 'c',
        path: 'c/02_Son_2026-09-09.mp3',
        originalName: 'Son.mp3',
        position: 1,
        date: DateTime(2026, 9, 9),
      ),
    ]);
    expect(
      {for (final p in plan) p.from: p.to},
      {
        'c/01_Son_2026-09-09.mp3': 'c/02_Son_2026-09-09.mp3',
        'c/02_Son_2026-09-09.mp3': 'c/01_Son_2026-09-09.mp3',
      },
    );
  });

  test('zip : les fichiers sont dans l’archive sous leur nom', () {
    final bytes = buildZip({
      '01_A_2026-09-09.mp3': Uint8List.fromList([1, 2, 3]),
      '02_B_2026-09-09.wav': Uint8List.fromList([4, 5]),
    });
    final decoded = ZipDecoder().decodeBytes(bytes);
    expect(decoded.files.map((f) => f.name), [
      '01_A_2026-09-09.mp3',
      '02_B_2026-09-09.wav',
    ]);
    expect(decoded.files.first.content, [1, 2, 3]);
  });

  test('recherche : % et _ sont cherchés tels quels', () {
    expect(likePattern(' 50%_ok '), r'%50\%\_ok%');
  });

  testWidgets('recherche : résultats groupés et ouverture', (tester) async {
    final search = FakeSearch([
      const SearchHit(
        kind: SearchKind.proposal,
        id: 'p1',
        title: 'Barrage de Sélingué',
        subtitle: 'Un angle',
        proposalId: 'p1',
      ),
      SearchHit(
        kind: SearchKind.sound,
        id: 'm1',
        title: '03_Barrage_2026-09-09.mp3',
        subtitle: 'Journal · Reportage',
        date: DateTime(2026, 9, 9),
      ),
    ]);
    await pumpApp(tester, search: search);
    await tester.tap(find.byTooltip('Rechercher'));
    await tester.pumpAndSettle();
    expect(find.text('Saisissez au moins 2 caractères.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'b');
    await tester.pump(const Duration(seconds: 1));
    expect(search.queries, isEmpty);

    await tester.enterText(find.byType(TextField), 'barrage');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(search.queries, ['barrage']);
    expect(find.text('Sujets'), findsOneWidget);
    expect(find.text('Sons'), findsOneWidget);
    expect(find.text('Barrage de Sélingué'), findsOneWidget);

    await tester.tap(find.text('03_Barrage_2026-09-09.mp3'));
    await tester.pumpAndSettle();
    expect(
      find.text('Espace Son'),
      findsWidgets,
    ); // on arrive dans l'Espace Son
  });

  testWidgets('recherche : aucun résultat', (tester) async {
    await pumpApp(tester, search: FakeSearch(const []));
    await tester.tap(find.byTooltip('Rechercher'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Aucun résultat.'), findsOneWidget);
  });

  testWidgets('archives : conducteurs passés regroupés par jour', (
    tester,
  ) async {
    final archive = FakeArchive(
      past: [
        Conductor(
          id: 'a1',
          title: 'Journal de 12h',
          broadcastDate: DateTime(2026, 1, 5),
          status: ConductorStatus.aired,
          broadcastTime: '12:00',
        ),
        Conductor(
          id: 'a2',
          title: 'Flash de 07h',
          broadcastDate: DateTime(2026, 1, 5),
          status: ConductorStatus.aired,
          broadcastTime: '07:00',
        ),
        Conductor(
          id: 'a3',
          title: 'Journal de 12h',
          broadcastDate: DateTime(2026, 1, 4),
          status: ConductorStatus.locked,
        ),
      ],
    );
    await pumpApp(tester, role: UserRole.journalist, archive: archive);
    await tester.tap(find.text('Conducteur').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Archives'));
    await tester.pumpAndSettle();
    expect(find.text('lundi 5 janvier 2026'), findsOneWidget);
    expect(find.text('dimanche 4 janvier 2026'), findsOneWidget);
    expect(find.text('Journal de 12h'), findsNWidgets(2));
    expect(find.text('Libérer de l’espace'), findsNothing); // réservé à l'admin
  });

  testWidgets('archives : libérer de l’espace, confirmation puis suppression', (
    tester,
  ) async {
    final archive = FakeArchive(sounds: [_sound('s1'), _sound('s2')]);
    final sound = st.FakeSound();
    await pumpApp(tester, archive: archive, sound: sound);
    await tester.tap(find.text('Conducteur').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Archives'));
    await tester.pumpAndSettle();
    expect(find.text('Libérer de l’espace'), findsOneWidget);

    await tester.tap(find.text('Rechercher'));
    await tester.pumpAndSettle();
    expect(find.text('Supprimer 2 sons ?'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(sound.deleted, isEmpty);

    await tester.tap(find.text('Rechercher'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer définitivement'));
    await tester.pumpAndSettle();
    expect(sound.deleted, ['s1', 's2']);
    expect(find.text('2 sons supprimés.'), findsOneWidget);
    // la période demandée : 90 jours avant aujourd'hui
    final n = DateTime.now();
    expect(
      archive.askedBefore,
      DateTime(n.year, n.month, n.day).subtract(const Duration(days: 90)),
    );
  });
}
