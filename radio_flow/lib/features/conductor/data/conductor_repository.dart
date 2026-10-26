import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/audio_naming.dart';
import '../../../data/local/local_store.dart';
import '../../../data/sync/sync_providers.dart';
import 'offline_conductor_repository.dart';
import '../domain/conductor_models.dart';

String isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

abstract class ConductorRepository {
  Stream<List<Conductor>> watchConductors(String isoDate);
  Stream<List<ConductorLine>> watchLines(String conductorId);
  Future<List<BroadcastSlot>> fetchSlots();

  /// Crée les conducteurs de la date d'après la grille; renvoie le nombre créé.
  Future<int> generate(DateTime date);
  Future<void> addSlot({
    required String title,
    required String time,
    List<int> weekdays = BroadcastSlot.allWeekdays,
    int? durationSeconds,
  });
  Future<void> removeSlot(String id);

  /// Texte à lire à l'antenne (null ou vide pour l'effacer).
  Future<void> setLineScript(String lineId, String? text);

  /// Enregistre les lignes du conducteur comme modèle de son créneau; renvoie leur nombre.
  Future<int> saveAsTemplate(String conductorId);

  /// Modifications du conducteur, les plus récentes d'abord.
  Future<List<HistoryEntry>> fetchHistory(String conductorId);

  /// Ajoute une ligne en fin de conducteur et renvoie son identifiant.
  Future<String> addLine({
    String? id,
    required String conductorId,
    required String title,
    required LineItemType type,
    int? plannedDuration,
  });
  Future<void> swapLines(String a, String b);
  Future<void> setConductorStatus(String id, ConductorStatus status);
  Future<void> setLineStatus(String id, LineStatus status);
}

class SupabaseConductorRepository implements ConductorRepository {
  SupabaseConductorRepository(this._client);
  final SupabaseClient _client;

  @override
  Stream<List<Conductor>> watchConductors(String isoDate) => _client
      .from('conductors')
      .stream(primaryKey: ['id'])
      .eq('broadcast_date', isoDate)
      .map((rows) {
        final list = rows.map(Conductor.fromJson).toList();
        list.sort(
          (a, b) => (a.broadcastTime ?? '99:99').compareTo(
            b.broadcastTime ?? '99:99',
          ),
        );
        return list;
      });

  @override
  Stream<List<ConductorLine>> watchLines(String conductorId) => _client
      .from('conductor_lines')
      .stream(primaryKey: ['id'])
      .eq('conductor_id', conductorId)
      .order('position_index')
      .map((rows) => rows.map(ConductorLine.fromJson).toList());

  @override
  Future<List<BroadcastSlot>> fetchSlots() async {
    final rows = await _client
        .from('broadcast_slots')
        .select()
        .order('broadcast_time');
    return rows.map(BroadcastSlot.fromJson).toList();
  }

  @override
  Future<int> generate(DateTime date) async {
    final n = await _client.rpc(
      'generate_conductors',
      params: {'p_date': isoDate(date)},
    );
    return (n as num).toInt();
  }

  @override
  Future<void> addSlot({
    required String title,
    required String time,
    List<int> weekdays = BroadcastSlot.allWeekdays,
    int? durationSeconds,
  }) async {
    await _client.from('broadcast_slots').insert({
      'title': title.trim(),
      'broadcast_time': time,
      'weekdays': weekdays,
      'duration_seconds': durationSeconds,
    });
  }

  @override
  Future<void> setLineScript(String lineId, String? text) async {
    await _client.rpc(
      'set_line_script',
      params: {'p_line_id': lineId, 'p_script': text ?? ''},
    );
  }

  @override
  Future<int> saveAsTemplate(String conductorId) async {
    final n = await _client.rpc(
      'save_conductor_as_template',
      params: {'p_conductor_id': conductorId},
    );
    return (n as num).toInt();
  }

  @override
  Future<List<HistoryEntry>> fetchHistory(String conductorId) async {
    final rows = await _client
        .from('conductor_history')
        .select()
        .eq('conductor_id', conductorId)
        .order('created_at', ascending: false)
        .limit(200);
    return rows.map(HistoryEntry.fromJson).toList();
  }

  @override
  Future<void> removeSlot(String id) async {
    await _client.from('broadcast_slots').delete().eq('id', id);
  }

  @override
  Future<String> addLine({
    String? id,
    required String conductorId,
    required String title,
    required LineItemType type,
    int? plannedDuration,
  }) async {
    final created = await _client.rpc(
      'add_conductor_line',
      params: {
        'p_conductor_id': conductorId,
        'p_title': title.trim(),
        'p_item_type': type.name,
        'p_planned_duration': plannedDuration,
        'p_id': ?id,
      },
    );
    return created as String;
  }

  @override
  Future<void> swapLines(String a, String b) async {
    await _client.rpc('swap_conductor_lines', params: {'p_a': a, 'p_b': b});
    // Les noms de fichiers portent la position : on les met à jour. Si cela échoue,
    // l'échange reste valable (les anciens noms restent lisibles et téléchargeables).
    try {
      await _renameSounds([a, b]);
    } catch (_) {}
  }

  Future<void> _renameSounds(List<String> lineIds) async {
    final rows = await _client
        .from('sound_files')
        .select()
        .inFilter('line_id', lineIds);
    final plan = planSoundRenames([
      for (final r in rows)
        (
          messageId: r['message_id'] as String,
          conductorId: r['conductor_id'] as String,
          path: r['storage_path'] as String,
          originalName: r['original_name'] as String?,
          position: r['position_index'] as int,
          date: DateTime.tryParse((r['broadcast_date'] as String?) ?? ''),
        ),
    ]);
    if (plan.isEmpty) return;
    final bucket = _client.storage.from('conductor-audio');
    // Deux étapes (nom provisoire) : deux fichiers peuvent échanger leurs noms sans collision.
    // En cas d'échec, les fichiers déjà déplacés reprennent leur nom d'origine.
    String tmp(SoundRename p) => '${p.conductorId}/.tmp-${p.messageId}';
    final parked = <SoundRename>[];
    try {
      for (final p in plan) {
        await bucket.move(p.from, tmp(p));
        parked.add(p);
      }
      for (final p in List.of(parked)) {
        await bucket.move(tmp(p), p.to);
        parked.remove(p);
        try {
          await _client
              .from('messages')
              .update({'audio_file_url': p.to})
              .eq('id', p.messageId);
        } catch (_) {
          await bucket.move(p.to, p.from);
          rethrow;
        }
      }
    } catch (_) {
      for (final p in parked) {
        try {
          await bucket.move(tmp(p), p.from);
        } catch (_) {}
      }
      rethrow;
    }
  }

  @override
  Future<void> setConductorStatus(String id, ConductorStatus status) async {
    await _client
        .from('conductors')
        .update({'status': status.name})
        .eq('id', id);
  }

  @override
  Future<void> setLineStatus(String id, LineStatus status) async {
    await _client
        .from('conductor_lines')
        .update({'status': status.dbValue})
        .eq('id', id);
  }
}

final conductorRemoteProvider = Provider<ConductorRepository>(
  (ref) => SupabaseConductorRepository(Supabase.instance.client),
);

final conductorRepositoryProvider = Provider<ConductorRepository>(
  (ref) => OfflineConductorRepository(
    remote: ref.watch(conductorRemoteProvider),
    store: ref.watch(localStoreProvider),
    sync: ref.watch(syncServiceProvider),
  ),
);

class SelectedDate extends Notifier<DateTime> {
  @override
  DateTime build() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  void set(DateTime d) => state = DateTime(d.year, d.month, d.day);
}

final selectedDateProvider = NotifierProvider<SelectedDate, DateTime>(
  SelectedDate.new,
);

final conductorsProvider = StreamProvider.autoDispose
    .family<List<Conductor>, String>(
      (ref, date) =>
          ref.watch(conductorRepositoryProvider).watchConductors(date),
    );

final linesProvider = StreamProvider.autoDispose
    .family<List<ConductorLine>, String>(
      (ref, conductorId) =>
          ref.watch(conductorRepositoryProvider).watchLines(conductorId),
    );

final historyProvider = FutureProvider.autoDispose
    .family<List<HistoryEntry>, String>(
      (ref, conductorId) =>
          ref.watch(conductorRepositoryProvider).fetchHistory(conductorId),
    );

final slotsProvider = FutureProvider.autoDispose<List<BroadcastSlot>>(
  (ref) => ref.watch(conductorRepositoryProvider).fetchSlots(),
);
