import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:radio_flow/data/local/local_store.dart';
import 'package:radio_flow/data/sync/sync_service.dart';
import 'package:radio_flow/features/conductor/data/conductor_repository.dart';
import 'package:radio_flow/features/conductor/data/offline_conductor_repository.dart';
import 'package:radio_flow/features/conductor/domain/conductor_models.dart';
import 'package:radio_flow/features/sound_space/data/offline_sound_repository.dart';
import 'package:radio_flow/features/sound_space/data/pending_audio_store.dart';
import 'package:radio_flow/features/sound_space/data/sound_repository.dart';
import 'package:radio_flow/features/sound_space/domain/sound_file.dart';

import 'offline_test.dart' show FakeConnectivity, memoryStore;

const _down = SocketException('Failed host lookup');

class RemoteConductors implements ConductorRepository {
  bool reachable = true;
  List<ConductorLine> lines = [];
  List<BroadcastSlot> slots = const [];
  final calls = <String>[];
  final _ctrl = StreamController<void>.broadcast();

  void _check() {
    if (!reachable) throw _down;
  }

  @override
  Stream<List<ConductorLine>> watchLines(String conductorId) async* {
    _check();
    yield List.of(lines);
    await for (final _ in _ctrl.stream) {
      yield List.of(lines);
    }
  }

  @override
  Stream<List<Conductor>> watchConductors(String isoDate) async* {
    _check();
    yield [
      Conductor(
        id: 'c1',
        title: 'Journal',
        broadcastDate: DateTime(2026, 9, 9),
        status: ConductorStatus.open,
        broadcastTime: '12:00',
      ),
    ];
  }

  @override
  Future<String> addLine({
    String? id,
    required String conductorId,
    required String title,
    required LineItemType type,
    int? plannedDuration,
  }) async {
    _check();
    calls.add('add:$id:$title');
    // idempotent, comme la fonction SQL : rejouer ne crée pas de doublon
    if (!lines.any((l) => l.id == id)) {
      lines = [
        ...lines,
        ConductorLine(
          id: id!,
          conductorId: conductorId,
          position: lines.length + 1,
          itemType: type,
          title: title,
          status: LineStatus.planned,
        ),
      ];
      _ctrl.add(null);
    }
    return id!;
  }

  @override
  Future<void> setLineStatus(String id, LineStatus status) async {
    _check();
    calls.add('status:$id:${status.dbValue}');
    lines = [
      for (final l in lines) l.id == id ? l.copyWith(status: status) : l,
    ];
    _ctrl.add(null);
  }

  @override
  Future<void> setLineScript(String lineId, String? text) async {
    _check();
    calls.add('script:$lineId:$text');
    lines = [
      for (final l in lines)
        l.id == lineId
            ? l.copyWith(
                script: text,
                clearScript: text == null || text.isEmpty,
              )
            : l,
    ];
    _ctrl.add(null);
  }

  @override
  Future<List<BroadcastSlot>> fetchSlots() async {
    _check();
    return slots;
  }

  @override
  Future<int> generate(DateTime date) async => 0;
  @override
  Future<void> addSlot({
    required String title,
    required String time,
    List<int> weekdays = BroadcastSlot.allWeekdays,
    int? durationSeconds,
  }) async {}
  @override
  Future<void> removeSlot(String id) async {}
  @override
  Future<int> saveAsTemplate(String conductorId) async => 0;
  @override
  Future<List<HistoryEntry>> fetchHistory(String conductorId) async => const [];
  @override
  Future<void> swapLines(String a, String b) async {}
  @override
  Future<void> setConductorStatus(String id, ConductorStatus status) async {}
}

class MemoryAudio implements PendingAudioStore {
  final saved = <String, Uint8List>{};
  @override
  Future<String> save(Uint8List bytes) async {
    final ref = 'f${saved.length + 1}';
    saved[ref] = bytes;
    return ref;
  }

  @override
  Future<Uint8List> read(String ref) async => saved[ref]!;
  @override
  Future<void> delete(String ref) async => saved.remove(ref);
}

class RemoteSound implements SoundRepository {
  bool reachable = true;
  bool duplicate = false;
  final uploads = <String>[];
  List<SoundFile> files = [];

  @override
  Future<List<SoundFile>> fetchFiles(String isoDate) async {
    if (!reachable) throw _down;
    return files;
  }

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
    int? durationSeconds,
  }) async {
    if (!reachable) throw _down;
    if (duplicate) throw const DuplicateAudioException('03_Son_2026-09-09.mp3');
    uploads.add(
      '$conductorId:$position:$originalName:${bytes.length}:$durationSeconds',
    );
    return 'stored';
  }

  @override
  Future<void> deleteSound(SoundFile file) async {}
  @override
  Future<String> signedUrl(String path) async => '';
  @override
  Future<Uint8List> download(String path) async => Uint8List(0);
}

ConductorLine _line(String id, int pos) => ConductorLine(
  id: id,
  conductorId: 'c1',
  position: pos,
  itemType: LineItemType.brief,
  title: 'L$pos',
  status: LineStatus.planned,
);

void main() {
  late LocalStore store;
  late FakeConnectivity net;
  late RemoteConductors remote;
  late SyncService sync;
  late OfflineConductorRepository repo;

  setUp(() {
    store = memoryStore();
    net = FakeConnectivity();
    remote = RemoteConductors();
    sync = SyncService(
      store: store,
      connectivity: net,
      retryEvery: const Duration(hours: 1),
      handlers: {
        OfflineConductorRepository.addLineKind: (p) =>
            OfflineConductorRepository.sendAddLine(remote, p),
        OfflineConductorRepository.lineStatusKind: (p) => remote.setLineStatus(
          p['id'] as String,
          LineStatus.parse(p['status'] as String),
        ),
        OfflineConductorRepository.lineScriptKind: (p) =>
            remote.setLineScript(p['id'] as String, p['text'] as String?),
      },
    );
    repo = OfflineConductorRepository(remote: remote, store: store, sync: sync);
  });

  test(
    'hors ligne : la ligne ajoutée apparaît puis est envoyée une seule fois',
    () async {
      remote.lines = [_line('l1', 1)];
      remote.reachable = false;
      final id = await repo.addLine(
        conductorId: 'c1',
        title: 'Brève ajoutée',
        type: LineItemType.brief,
      );
      expect((await store.items()).single.kind, 'line.add');

      final shown = OfflineConductorRepository.overlay('c1', [
        _line('l1', 1),
      ], await store.items());
      expect(shown.map((l) => l.title), ['L1', 'Brève ajoutée']);
      expect(shown.last.pendingSync, isTrue);
      expect(shown.last.position, 2);

      remote.reachable = true;
      await sync.flush();
      expect(await store.items(), isEmpty);
      expect(remote.lines.map((l) => l.id), ['l1', id]);

      // réponse perdue puis rejeu : toujours une seule ligne
      await OfflineConductorRepository.sendAddLine(remote, {
        'id': id,
        'conductor_id': 'c1',
        'title': 'Brève ajoutée',
        'item_type': 'brief',
        'planned_duration': null,
      });
      expect(remote.lines, hasLength(2));
    },
  );

  test(
    'hors ligne : statut et texte de ligne en attente, appliqués dans l’ordre',
    () async {
      remote.lines = [_line('l1', 1)];
      remote.reachable = false;
      await repo.setLineStatus('l1', LineStatus.ready);
      await repo.setLineScript('l1', 'Bonjour');
      await repo.setLineScript('l1', 'Bonsoir');

      final shown = OfflineConductorRepository.overlay('c1', [
        _line('l1', 1),
      ], await store.items());
      expect(shown.single.status, LineStatus.ready);
      expect(shown.single.script, 'Bonsoir');
      expect(shown.single.pendingSync, isTrue);

      remote.reachable = true;
      await sync.flush();
      expect(remote.calls, [
        'status:l1:ready',
        'script:l1:Bonjour',
        'script:l1:Bonsoir',
      ]);
      expect(remote.lines.single.script, 'Bonsoir');
    },
  );

  test(
    'une opération en attente passe devant, même une fois le réseau revenu',
    () async {
      remote.lines = [_line('l1', 1)];
      remote.reachable = false;
      await repo.setLineStatus('l1', LineStatus.ready);
      remote.reachable =
          true; // réseau revenu mais la file n'est pas encore vidée
      await repo.setLineStatus('l1', LineStatus.aired);
      expect(remote.calls, isEmpty);
      expect(await store.items(), hasLength(2));
      await sync.flush();
      expect(remote.calls, ['status:l1:ready', 'status:l1:aired']);
    },
  );

  test('en ligne : envoi direct, rien en file', () async {
    remote.lines = [_line('l1', 1)];
    await repo.setLineStatus('l1', LineStatus.ready);
    expect(remote.calls, ['status:l1:ready']);
    expect(await store.items(), isEmpty);
  });

  test('une erreur du serveur n’est pas mise en file', () async {
    remote.lines = [];
    final failing = OfflineConductorRepository(
      remote: _Refusing(),
      store: store,
      sync: sync,
    );
    await expectLater(
      failing.setLineStatus('l1', LineStatus.ready),
      throwsA(isA<StateError>()),
    );
    expect(await store.items(), isEmpty);
  });

  test('grille : dernière version affichée sans réseau', () async {
    remote.slots = const [
      BroadcastSlot(id: 's1', title: 'Flash', time: '07:00', active: true),
    ];
    expect((await repo.fetchSlots()).single.title, 'Flash');
    remote.reachable = false;
    final cached = await repo.fetchSlots();
    expect(cached.single.title, 'Flash');
    expect(cached.single.time, '07:00');
  });

  test('lignes : la copie locale est servie sans réseau', () async {
    remote.lines = [_line('l1', 1)];
    final first = await repo.watchLines('c1').first;
    expect(first.single.id, 'l1');
    remote.reachable = false;
    final offline = await repo.watchLines('c1').first;
    expect(offline.single.title, 'L1');
  });

  group('sons', () {
    late RemoteSound sounds;
    late MemoryAudio audio;
    late OfflineSoundRepository soundRepo;

    setUp(() {
      sounds = RemoteSound();
      audio = MemoryAudio();
      soundRepo = OfflineSoundRepository(
        remote: sounds,
        store: store,
        sync: sync,
        files: audio,
      );
    });

    Future<String> send() => soundRepo.upload(
      conductorId: 'c1',
      threadId: 't1',
      userId: 'u1',
      position: 3,
      date: DateTime(2026, 9, 9),
      originalName: 'Son.mp3',
      bytes: Uint8List.fromList([1, 2, 3, 4]),
      durationSeconds: 42,
    );

    test('hors ligne : le son est gardé sur l’appareil puis envoyé', () async {
      sounds.reachable = false;
      final name = await send();
      expect(name, '03_Son_2026-09-09.mp3');
      expect(audio.saved, hasLength(1));
      expect((await store.items()).single.kind, 'sound.upload');

      sounds.reachable = true;
      sync = SyncService(
        store: store,
        connectivity: net,
        retryEvery: const Duration(hours: 1),
        handlers: {
          OfflineSoundRepository.uploadKind: (p) =>
              OfflineSoundRepository.sendUpload(sounds, audio, p),
        },
      );
      await sync.flush();
      expect(sounds.uploads, ['c1:3:Son.mp3:4:42']);
      expect(audio.saved, isEmpty);
      expect(await store.items(), isEmpty);
    });

    test('en ligne : envoi direct', () async {
      await send();
      expect(sounds.uploads, hasLength(1));
      expect(audio.saved, isEmpty);
    });

    test(
      'nom déjà pris à l’envoi différé : refus visible, fichier conservé',
      () async {
        sounds.reachable = false;
        await send();
        sounds.reachable = true;
        sounds.duplicate = true;
        sync = SyncService(
          store: store,
          connectivity: net,
          retryEvery: const Duration(hours: 1),
          handlers: {
            OfflineSoundRepository.uploadKind: (p) =>
                OfflineSoundRepository.sendUpload(sounds, audio, p),
          },
        );
        await sync.flush();
        final item = (await store.items()).single;
        expect(item.failed, isTrue);
        expect(item.error, contains('existe déjà'));
        expect(audio.saved, hasLength(1)); // rien n'est perdu
      },
    );

    test('liste des sons : dernière version affichée sans réseau', () async {
      sounds.files = [
        SoundFile(
          messageId: 'm1',
          conductorId: 'c1',
          conductorTitle: 'Journal',
          broadcastTime: '12:00',
          lineId: 'l1',
          position: 1,
          lineTitle: 'L1',
          storagePath: 'c1/01_A_2026-09-09.mp3',
          uploadedBy: 'u1',
          uploadedAt: DateTime.utc(2026, 9, 9, 8),
          originalName: 'A.mp3',
          duration: 61,
          broadcastDate: DateTime(2026, 9, 9),
        ),
      ];
      expect((await soundRepo.fetchFiles('2026-09-09')).single.duration, 61);
      sounds.reachable = false;
      final cached = await soundRepo.fetchFiles('2026-09-09');
      expect(cached.single.storedName, '01_A_2026-09-09.mp3');
      expect(cached.single.broadcastDate, DateTime(2026, 9, 9));
    });
  });
}

class _Refusing extends RemoteConductors {
  @override
  Future<void> setLineStatus(String id, LineStatus status) async {
    throw StateError('refusé par le serveur');
  }
}
