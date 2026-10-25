import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../sound_space/data/sound_repository.dart';
import '../../tasks/data/tasks_repository.dart';
import '../../tasks/domain/task_models.dart';
import '../../auth/data/profile_repository.dart';
import '../domain/report.dart';

abstract class DashboardRepository {
  Future<List<ProductionRow>> fetchStats(DateRange range);
}

class SupabaseDashboardRepository implements DashboardRepository {
  SupabaseDashboardRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<ProductionRow>> fetchStats(DateRange range) async {
    final f = DateFormat('yyyy-MM-dd');
    final rows = await _client.rpc(
      'production_stats',
      params: {'p_from': f.format(range.from), 'p_to': f.format(range.to)},
    );
    return (rows as List)
        .map((r) => ProductionRow.fromJson(r as Map<String, dynamic>))
        .toList();
  }
}

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => SupabaseDashboardRepository(Supabase.instance.client),
);

class PeriodSelection {
  const PeriodSelection(this.kind, this.range);
  final PeriodKind kind;
  final DateRange range;
}

class PeriodNotifier extends Notifier<PeriodSelection> {
  @override
  PeriodSelection build() =>
      PeriodSelection(PeriodKind.week, DateRange.week(DateTime.now()));

  void week() =>
      state = PeriodSelection(PeriodKind.week, DateRange.week(DateTime.now()));
  void month() => state = PeriodSelection(
    PeriodKind.month,
    DateRange.month(DateTime.now()),
  );
  void custom(DateRange r) => state = PeriodSelection(PeriodKind.custom, r);
}

final periodProvider = NotifierProvider<PeriodNotifier, PeriodSelection>(
  PeriodNotifier.new,
);

/// Bilan de la période choisie. Se recalcule quand une tâche change ou qu'un son est publié.
final reportProvider = FutureProvider.autoDispose<DashboardReport>((ref) async {
  final range = ref.watch(periodProvider).range;
  final tasks = ref.watch(tasksProvider).value ?? const <TeamTask>[];
  final names =
      ref.watch(authorNamesProvider).value ?? const <String, String>{};
  final sub = ref
      .watch(soundRepositoryProvider)
      .changes()
      .listen((_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);

  final rows = await ref.watch(dashboardRepositoryProvider).fetchStats(range);
  final open = tasks
      .where((t) => !t.isDone)
      .map(
        (t) => OpenTaskLine(
          owner: names[t.userId] ?? 'Membre',
          title: t.title,
          status: t.status.label,
          due: t.dueDate,
        ),
      );
  final sorted = open.toList()
    ..sort((a, b) {
      final byOwner = a.owner.compareTo(b.owner);
      return byOwner != 0
          ? byOwner
          : (a.due ?? DateTime(9999)).compareTo(b.due ?? DateTime(9999));
    });
  return DashboardReport(
    range: range,
    rows: rows,
    openTasks: sorted,
    generatedAt: DateTime.now(),
  );
});
