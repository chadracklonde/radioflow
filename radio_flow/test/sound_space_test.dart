import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:radio_flow/app.dart';
import 'package:radio_flow/core/utils/audio_naming.dart';
import 'package:radio_flow/features/auth/data/auth_repository.dart';
import 'package:radio_flow/features/auth/data/profile_repository.dart';
import 'package:radio_flow/features/conductor/data/conductor_repository.dart';
import 'package:radio_flow/features/conductor/domain/conductor_models.dart';
import 'package:radio_flow/features/sound_space/data/audio_services.dart';
import 'package:radio_flow/features/sound_space/data/sound_repository.dart';
import 'package:radio_flow/features/sound_space/domain/sound_file.dart';
import 'package:radio_flow/features/threads/data/thread_repository.dart';
import 'package:radio_flow/features/threads/domain/thread_message.dart';

class _SignedIn implements AuthRepository {
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

class _Profiles implements ProfileRepository {
  _Profiles(this.role);
  final UserRole role;
  @override
  Future<Profile?> fetchMe() async =>
      Profile(id: 'u1', fullName: 'Awa Traoré', role: role);
  @override
  Future<Map<String, String>> fetchNames() async => {'u1': 'Awa Traoré'};
}

final _today = DateTime.now();
final _day = DateTime(_today.year, _today.month, _today.day);

class _Conductors implements ConductorRepository {
  _Conductors(this.status);
  final ConductorStatus status;
  @override
  Stream<List<Conductor>> watchConductors(String isoDate) => Stream.value([
    Conductor(
      id: 'c1',
      title: 'Journal de 12h',
      broadcastDate: _day,
      status: status,
      broadcastTime: '12:00',
    ),
  ]);
  @override
  Stream<List<ConductorLine>> watchLines(String conductorId) => Stream.value([
    const ConductorLine(
      id: 'l3',
      conductorId: 'c1',
      position: 3,
      itemType: LineItemType.reportage,
      title: 'Marché de Bamako',
      status: LineStatus.planned,
    ),
  ]);
  @override
  Future<List<BroadcastSlot>> fetchSlots() async => const [];
  @override
  Future<int> generate(DateTime date) async => 0;
  @override
  Future<void> addSlot({required String title, required String time}) async {}
  @override
  Future<void> addLine({
    required String conductorId,
    required String title,
    required LineItemType type,
    int? plannedDuration,
  }) async {}
  @override
  Future<void> swapLines(String a, String b) async {}
  @override
  Future<void> setConductorStatus(String id, ConductorStatus status) async {}
  @override
  Future<void> setLineStatus(String id, LineStatus status) async {}
}

class _Threads implements ThreadRepository {
  @override
  Future<String> threadIdForLine(String lineId) async => 't-$lineId';
  @override
  Stream<List<ThreadMessage>> watchMessages(String threadId) =>
      Stream.value(const []);
  @override
  Future<void> sendText({
    String? id,
    required String threadId,
    required String userId,
    required String text,
  }) async {}
}

class FakeSound implements SoundRepository {
  FakeSound({this.duplicate = false});
  final bool duplicate;
  final uploads = <String>[];
  final played = <String>[];

  List<SoundFile> files = [
    SoundFile(
      messageId: 'm1',
      conductorId: 'c1',
      conductorTitle: 'Journal de 12h',
      broadcastTime: '12:00',
      lineId: 'l3',
      position: 3,
      lineTitle: 'Marché de Bamako',
      storagePath: 'c1/03_Reportage_Marche_2026-09-09.mp3',
      uploadedBy: 'u1',
      uploadedAt: DateTime(2026, 9, 9, 9, 30),
      originalName: 'Reportage Marché.mp3',
      duration: 95,
    ),
  ];

  @override
  Future<List<SoundFile>> fetchFiles(String isoDate) async => files;
  @override
  Stream<void> changes() => const Stream.empty();
  @override
  Future<String> upload({
    required String conductorId,
    required String threadId,
    required String userId,
    required int position,
    required DateTime date,
    required String originalName,
    required Uint8List bytes,
  }) async {
    final stored = audioStoredName(
      position: position,
      originalName: originalName,
      date: date,
    );
    if (duplicate) throw DuplicateAudioException(stored);
    uploads.add('$conductorId/$stored:${bytes.length}');
    return stored;
  }

  @override
  Future<String> signedUrl(String path) async => 'https://signed/$path';
  @override
  Future<Uint8List> download(String path) async =>
      Uint8List.fromList([1, 2, 3]);
}

class FakeFiles implements AudioFileService {
  FakeFiles(this.next);
  PickedAudio? next;
  final saved = <String>[];
  @override
  Future<PickedAudio?> pick() async => next;
  @override
  Future<bool> save({
    required String fileName,
    required Uint8List bytes,
  }) async {
    saved.add('$fileName:${bytes.length}');
    return true;
  }
}

class FakePlayer implements AudioPlayerService {
  final urls = <String>[];
  int stops = 0;
  @override
  Future<void> play(String url) async => urls.add(url);
  @override
  Future<void> stop() async => stops++;
  @override
  Stream<void> get completed => const Stream.empty();
  @override
  void dispose() {}
}

PickedAudio _audio(String name, {int size = 3}) =>
    PickedAudio(name: name, size: size, readBytes: () async => Uint8List(size));

class TestEnv {
  TestEnv(this.sound, this.files, this.player);
  final FakeSound sound;
  final FakeFiles files;
  final FakePlayer player;
}

Future<TestEnv> pump(
  WidgetTester tester,
  String tab, {
  UserRole role = UserRole.journalist,
  ConductorStatus status = ConductorStatus.open,
  FakeSound? sound,
  PickedAudio? pick,
}) async {
  await initializeDateFormatting('fr');
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final env = TestEnv(sound ?? FakeSound(), FakeFiles(pick), FakePlayer());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_SignedIn()),
        profileRepositoryProvider.overrideWithValue(_Profiles(role)),
        conductorRepositoryProvider.overrideWithValue(_Conductors(status)),
        threadRepositoryProvider.overrideWithValue(_Threads()),
        soundRepositoryProvider.overrideWithValue(env.sound),
        audioFileServiceProvider.overrideWithValue(env.files),
        audioPlayerProvider.overrideWithValue(env.player),
      ],
      child: const RadioFlowApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(tab).last);
  await tester.pumpAndSettle();
  return env;
}

Future<void> openThread(WidgetTester tester) async {
  await tester.tap(find.text('Journal de 12h'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Marché de Bamako'));
  await tester.pumpAndSettle();
}

void main() {
  group('nommage automatique', () {
    test('exemple du cahier des charges', () {
      expect(
        audioStoredName(
          position: 3,
          originalName: 'Reportage Marche.mp3',
          date: DateTime(2026, 9, 9),
        ),
        '03_Reportage_Marche_2026-09-09.mp3',
      );
    });
    test('accents, ponctuation, extension en minuscules', () {
      expect(
        audioStoredName(
          position: 12,
          originalName: 'Interview – Ministre (élu).WAV',
          date: DateTime(2026, 1, 5),
        ),
        '12_Interview_Ministre_elu_2026-01-05.wav',
      );
      expect(
        audioStoredName(
          position: 1,
          originalName: 'Cœur de l’été.mp3',
          date: DateTime(2026, 9, 9),
        ),
        '01_Coeur_de_l_ete_2026-09-09.mp3',
      );
    });
    test('nom vide ou sans extension', () {
      expect(
        audioStoredName(
          position: 7,
          originalName: '!!!.mp3',
          date: DateTime(2026, 9, 9),
        ),
        '07_audio_2026-09-09.mp3',
      );
      expect(
        audioStoredName(
          position: 7,
          originalName: 'son',
          date: DateTime(2026, 9, 9),
        ),
        '07_son_2026-09-09',
      );
    });
    test('validation', () {
      expect(AudioRules.validate(name: 'a.mp3', size: 10), isNull);
      expect(AudioRules.validate(name: 'a.exe', size: 10), contains('Format'));
      expect(AudioRules.validate(name: 'a.mp3', size: 0), contains('vide'));
      expect(
        AudioRules.validate(name: 'a.mp3', size: AudioRules.maxBytes + 1),
        contains('volumineux'),
      );
    });
  });

  testWidgets(
    'journaliste : envoie un audio depuis le fil, renommé avec la position',
    (tester) async {
      final env = await pump(
        tester,
        'Conducteur',
        pick: _audio('Reportage Marché.mp3', size: 5),
      );
      await openThread(tester);
      await tester.tap(find.byTooltip('Envoyer un fichier audio'));
      await tester.pumpAndSettle();
      expect(
        env.sound.uploads.single,
        'c1/03_Reportage_Marche_${_fmt(_day)}.mp3:5',
      );
      expect(
        find.textContaining('Envoyé sous le nom 03_Reportage_Marche_'),
        findsOneWidget,
      );
    },
  );

  testWidgets('format refusé : rien n’est envoyé', (tester) async {
    final env = await pump(tester, 'Conducteur', pick: _audio('virus.exe'));
    await openThread(tester);
    await tester.tap(find.byTooltip('Envoyer un fichier audio'));
    await tester.pumpAndSettle();
    expect(env.sound.uploads, isEmpty);
    expect(find.textContaining('Format non pris en charge'), findsOneWidget);
  });

  testWidgets('doublon : message clair', (tester) async {
    await pump(
      tester,
      'Conducteur',
      sound: FakeSound(duplicate: true),
      pick: _audio('a.mp3'),
    );
    await openThread(tester);
    await tester.tap(find.byTooltip('Envoyer un fichier audio'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('existe déjà dans cette édition'),
      findsOneWidget,
    );
  });

  testWidgets(
    'conducteur verrouillé : pas d’upload pour un journaliste, permis pour l’admin',
    (tester) async {
      await pump(tester, 'Conducteur', status: ConductorStatus.locked);
      await openThread(tester);
      expect(find.byTooltip('Envoyer un fichier audio'), findsNothing);
    },
  );

  testWidgets('admin : upload possible malgré le verrouillage', (tester) async {
    await pump(
      tester,
      'Conducteur',
      role: UserRole.admin,
      status: ConductorStatus.locked,
    );
    await openThread(tester);
    expect(find.byTooltip('Envoyer un fichier audio'), findsOneWidget);
  });

  testWidgets('technicien : pas de bouton d’envoi', (tester) async {
    await pump(tester, 'Conducteur', role: UserRole.technician);
    await openThread(tester);
    expect(find.byTooltip('Envoyer un fichier audio'), findsNothing);
  });

  testWidgets('Espace Son : liste, lecture, arrêt et téléchargement', (
    tester,
  ) async {
    final env = await pump(tester, 'Espace Son', role: UserRole.technician);
    expect(find.text('Journal de 12h'), findsOneWidget);
    expect(find.text('03_Reportage_Marche_2026-09-09.mp3'), findsOneWidget);
    expect(
      find.textContaining('Marché de Bamako · Awa Traoré'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Écouter'));
    await tester.pumpAndSettle();
    expect(env.player.urls, [
      'https://signed/c1/03_Reportage_Marche_2026-09-09.mp3',
    ]);
    expect(find.byTooltip('Arrêter la lecture'), findsOneWidget);

    await tester.tap(find.byTooltip('Arrêter la lecture'));
    await tester.pumpAndSettle();
    expect(env.player.stops, 1);
    expect(find.byTooltip('Écouter'), findsOneWidget);

    await tester.tap(find.byTooltip('Télécharger'));
    await tester.pumpAndSettle();
    expect(env.files.saved, ['03_Reportage_Marche_2026-09-09.mp3:3']);
  });

  testWidgets('Espace Son vide', (tester) async {
    await pump(tester, 'Espace Son', sound: FakeSound()..files = []);
    expect(
      find.textContaining('Aucun fichier audio ce jour-là'),
      findsOneWidget,
    );
  });
}

String _fmt(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
