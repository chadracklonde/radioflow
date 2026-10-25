import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/file_saver.dart';
import '../data/dashboard_repository.dart';
import '../data/report_export.dart';
import '../domain/report.dart';

/// Tableau de bord global : classement des productions et tâches en cours.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(periodProvider);
    final report = ref.watch(reportProvider);
    final c = context.colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          _PeriodBar(selection: period, report: report.value),
          Expanded(
            child: report.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off, size: 40, color: c.mutedForeground),
                    const SizedBox(height: Space.md),
                    const Text('Impossible de charger le bilan.'),
                    TextButton(
                      onPressed: () => ref.invalidate(reportProvider),
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
              data: (r) => RefreshIndicator(
                onRefresh: () => ref.refresh(reportProvider.future),
                child: ListView(
                  padding: const EdgeInsets.all(Space.lg),
                  children: [
                    _Kpis(report: r),
                    const SizedBox(height: Space.xl),
                    Text(
                      'Classement des productions',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      'Sons publiés dans les fils, du plus au moins productif.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: Space.md),
                    if (r.rows.isEmpty)
                      Text(
                        'Aucun journaliste pour le moment.',
                        style: TextStyle(color: c.mutedForeground),
                      )
                    else
                      for (var i = 0; i < r.rows.length; i++) ...[
                        _RankRow(
                          rank: i + 1,
                          row: r.rows[i],
                          max: r.rows.first.audioCount,
                        ),
                        const SizedBox(height: Space.sm),
                      ],
                    const SizedBox(height: Space.xl),
                    Text(
                      'Tâches en cours (${r.totalOpen})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: Space.md),
                    if (r.openTasks.isEmpty)
                      Text(
                        'Aucune tâche en cours.',
                        style: TextStyle(color: c.mutedForeground),
                      )
                    else
                      for (final t in r.openTasks) _OpenTaskTile(task: t),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodBar extends ConsumerWidget {
  const _PeriodBar({required this.selection, required this.report});
  final PeriodSelection selection;
  final DashboardReport? report;

  Future<void> _export(BuildContext context, WidgetRef ref, bool pdf) async {
    final r = report;
    if (r == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = pdf ? await buildPdf(r) : buildXlsx(r);
      final name = '${exportBaseName(r)}.${pdf ? 'pdf' : 'xlsx'}';
      final saved = await ref
          .read(fileSaverProvider)
          .save(
            fileName: name,
            bytes: bytes,
            mimeType: pdf ? 'application/pdf' : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          );
      if (saved) {
        messenger.showSnackBar(SnackBar(content: Text('$name enregistré.')));
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Export impossible. Réessayez.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(periodProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.md,
        Space.lg,
        Space.sm,
      ),
      child: Wrap(
        spacing: Space.md,
        runSpacing: Space.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<PeriodKind>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: PeriodKind.week, label: Text('Semaine')),
              ButtonSegment(value: PeriodKind.month, label: Text('Mois')),
              ButtonSegment(
                value: PeriodKind.custom,
                label: Text('Sur mesure'),
              ),
            ],
            selected: {selection.kind},
            onSelectionChanged: (s) async {
              switch (s.first) {
                case PeriodKind.week:
                  notifier.week();
                case PeriodKind.month:
                  notifier.month();
                case PeriodKind.custom:
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2024),
                    lastDate: DateTime(2100),
                    initialDateRange: DateTimeRange(
                      start: selection.range.from,
                      end: selection.range.to,
                    ),
                    locale: const Locale('fr'),
                  );
                  if (picked != null) {
                    notifier.custom(DateRange(picked.start, picked.end));
                  }
              }
            },
          ),
          Text(
            selection.range.label(),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('PDF'),
            onPressed: report == null
                ? null
                : () => _export(context, ref, true),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.table_chart_outlined),
            label: const Text('Excel'),
            onPressed: report == null
                ? null
                : () => _export(context, ref, false),
          ),
        ],
      ),
    );
  }
}

class _Kpis extends StatelessWidget {
  const _Kpis({required this.report});
  final DashboardReport report;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Sons publiés', report.totalAudio, Icons.audiotrack),
      ('Sujets validés', report.totalApproved, Icons.how_to_vote_outlined),
      ('Tâches terminées', report.totalDone, Icons.check_circle_outline),
      ('Tâches en cours', report.totalOpen, Icons.pending_actions),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final cols = box.maxWidth >= 640 ? 4 : 2;
        final width = (box.maxWidth - Space.md * (cols - 1)) / cols;
        return Wrap(
          spacing: Space.md,
          runSpacing: Space.md,
          children: [
            for (final (label, value, icon) in items)
              SizedBox(
                width: width,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          icon,
                          size: 20,
                          color: context.colors.mutedForeground,
                        ),
                        const SizedBox(height: Space.sm),
                        Text(
                          '$value',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                fontFamily: 'FiraCode',
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        Text(
                          label,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.rank, required this.row, required this.max});
  final int rank;
  final ProductionRow row;
  final int max;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final ratio = max == 0 ? 0.0 : row.audioCount / max;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text(
                '$rank',
                style: text.titleMedium?.copyWith(
                  fontFamily: 'FiraCode',
                  color: c.success,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(row.name, style: text.bodyLarge)),
                      Text(
                        '${row.audioCount} son${row.audioCount > 1 ? 's' : ''}',
                        style: text.titleMedium?.copyWith(
                          fontFamily: 'FiraCode',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 6,
                      backgroundColor: c.muted,
                      color: c.success,
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                  Text(
                    '${row.approvedProposals} sujet${row.approvedProposals > 1 ? 's' : ''} validé${row.approvedProposals > 1 ? 's' : ''} · '
                    '${row.tasksDone} tâche${row.tasksDone > 1 ? 's' : ''} terminée${row.tasksDone > 1 ? 's' : ''} · ${row.tasksOpen} en cours',
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpenTaskTile extends StatelessWidget {
  const _OpenTaskTile({required this.task});
  final OpenTaskLine task;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(Icons.person_outline, color: c.mutedForeground),
      title: Text(task.title),
      subtitle: Text(
        '${task.owner} · ${task.status}${task.due == null ? '' : ' · échéance ${DateFormat('d MMM', 'fr').format(task.due!)}'}',
        style: text.bodySmall,
      ),
    );
  }
}
