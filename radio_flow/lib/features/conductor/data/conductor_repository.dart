import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  });
  Future<void> removeSlot(String id);

  /// Ajoute une ligne en fin de conducteur et renvoie son identifiant.
  Future<String> addLine({
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
  }) async {
    await _client.from('broadcast_slots').insert({
      'title': title.trim(),
      'broadcast_time': time,
      'weekdays': weekdays,
    });
  }

  @override
  Future<void> removeSlot(String id) async {
    await _client.from('broadcast_slots').delete().eq('id', id);
  }

  @override
  Future<String> addLine({
    required String conductorId,
    required String title,
    required LineItemType type,
    int? plannedDuration,
  }) async {
    final id = await _client.rpc(
      'add_conductor_line',
      params: {
        'p_conductor_id': conductorId,
        'p_title': title.trim(),
        'p_item_type': type.name,
        'p_planned_duration': plannedDuration,
      },
    );
    return id as String;
  }

  @override
  Future<void> swapLines(String a, String b) async {
    await _client.rpc('swap_conductor_lines', params: {'p_a': a, 'p_b': b});
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

final conductorRepositoryProvider = Provider<ConductorRepository>(
  (ref) => SupabaseConductorRepository(Supabase.instance.client),
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

final slotsProvider = FutureProvider.autoDispose<List<BroadcastSlot>>(
  (ref) => ref.watch(conductorRepositoryProvider).fetchSlots(),
);
