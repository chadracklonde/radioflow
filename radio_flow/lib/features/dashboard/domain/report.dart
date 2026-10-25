import 'package:intl/intl.dart';

enum PeriodKind { week, month, custom }

class DateRange {
  const DateRange(this.from, this.to);
  final DateTime from;
  final DateTime to;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Semaine en cours, du lundi au dimanche.
  factory DateRange.week(DateTime now) {
    final d = _day(now);
    final monday = d.subtract(Duration(days: d.weekday - 1));
    return DateRange(monday, monday.add(const Duration(days: 6)));
  }

  /// Mois en cours, du 1er au dernier jour.
  factory DateRange.month(DateTime now) => DateRange(
    DateTime(now.year, now.month, 1),
    DateTime(now.year, now.month + 1, 0),
  );

  String label() {
    final f = DateFormat('d MMM yyyy', 'fr');
    return from == to ? f.format(from) : '${f.format(from)} – ${f.format(to)}';
  }
}

class ProductionRow {
  const ProductionRow({
    required this.userId,
    required this.name,
    required this.audioCount,
    required this.approvedProposals,
    required this.tasksDone,
    required this.tasksOpen,
  });

  final String userId;
  final String name;
  final int audioCount;
  final int approvedProposals;
  final int tasksDone;
  final int tasksOpen;

  factory ProductionRow.fromJson(Map<String, dynamic> j) => ProductionRow(
    userId: j['user_id'] as String,
    name: j['full_name'] as String,
    audioCount: (j['audio_count'] as num).toInt(),
    approvedProposals: (j['approved_proposals'] as num).toInt(),
    tasksDone: (j['tasks_done'] as num).toInt(),
    tasksOpen: (j['tasks_open'] as num).toInt(),
  );
}

class OpenTaskLine {
  const OpenTaskLine({
    required this.owner,
    required this.title,
    required this.status,
    this.due,
  });
  final String owner;
  final String title;
  final String status;
  final DateTime? due;
}

/// Données d'un bilan, utilisées par l'écran et par les exports.
class DashboardReport {
  const DashboardReport({
    required this.range,
    required this.rows,
    required this.openTasks,
    required this.generatedAt,
  });

  final DateRange range;
  final List<ProductionRow> rows;
  final List<OpenTaskLine> openTasks;
  final DateTime generatedAt;

  int get totalAudio => rows.fold(0, (s, r) => s + r.audioCount);
  int get totalApproved => rows.fold(0, (s, r) => s + r.approvedProposals);
  int get totalDone => rows.fold(0, (s, r) => s + r.tasksDone);
  int get totalOpen => openTasks.length;
}
