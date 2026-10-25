import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/data/profile_repository.dart';
import '../data/conductor_repository.dart';
import '../domain/conductor_models.dart';
import 'line_form.dart';

/// Lignes d'un conducteur, minute par minute.
class ConductorDetailScreen extends ConsumerWidget {
  const ConductorDetailScreen({
    super.key,
    required this.conductorId,
    required this.date,
  });

  final String conductorId;

  /// Date au format yyyy-MM-dd, pour retrouver le conducteur dans le flux du jour.
  final String date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conductor = ref
        .watch(conductorsProvider(date))
        .value
        ?.where((c) => c.id == conductorId)
        .firstOrNull;
    final lines = ref.watch(linesProvider(conductorId));
    final isAdmin = ref.watch(profileProvider).value?.isAdmin ?? false;
    final c = context.colors;
    final repo = ref.read(conductorRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(conductor?.title ?? 'Conducteur'),
        actions: [
          if (isAdmin && conductor != null)
            PopupMenuButton<ConductorStatus>(
              tooltip: 'Statut du conducteur',
              icon: const Icon(Icons.more_vert),
              onSelected: (s) => repo.setConductorStatus(conductorId, s),
              itemBuilder: (_) => [
                for (final s in ConductorStatus.values)
                  CheckedPopupMenuItem(
                    value: s,
                    checked: s == conductor.status,
                    child: Text(s.label),
                  ),
              ],
            ),
        ],
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => showLineForm(context, ref, conductorId),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter une ligne'),
            )
          : null,
      body: Column(
        children: [
          if (conductor != null && conductor.status.isLocked)
            Container(
              width: double.infinity,
              color: c.muted,
              padding: const EdgeInsets.symmetric(
                horizontal: Space.lg,
                vertical: Space.md,
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_outline, size: 18, color: c.warning),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      '${conductor.status.label} : plus d’upload audio possible.',
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: lines.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const Center(
                child: Text('Impossible de charger les lignes.'),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return Center(
                    child: Text(
                      isAdmin
                          ? 'Aucune ligne. Ajoutez la première.'
                          : 'Aucune ligne pour le moment.',
                      style: TextStyle(color: c.mutedForeground),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    Space.lg,
                    Space.lg,
                    96,
                  ),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
                  itemBuilder: (_, i) => _LineTile(
                    line: list[i],
                    previous: i > 0 ? list[i - 1] : null,
                    next: i < list.length - 1 ? list[i + 1] : null,
                    isAdmin: isAdmin,
                    conductorId: conductorId,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LineTile extends ConsumerWidget {
  const _LineTile({
    required this.line,
    required this.previous,
    required this.next,
    required this.isAdmin,
    required this.conductorId,
  });

  final ConductorLine line;
  final ConductorLine? previous;
  final ConductorLine? next;
  final bool isAdmin;
  final String conductorId;

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Action impossible. Réessayez.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final repo = ref.read(conductorRepositoryProvider);
    final dim = line.status == LineStatus.dropped;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/conductor/$conductorId/line/${line.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.md,
            vertical: Space.sm,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  line.position.toString().padLeft(2, '0'),
                  style: text.titleMedium?.copyWith(
                    fontFamily: 'FiraCode',
                    color: c.success,
                  ),
                ),
              ),
              Icon(
                line.itemType.icon,
                color: c.mutedForeground,
                semanticLabel: line.itemType.label,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.title,
                      style: text.bodyLarge?.copyWith(
                        decoration: dim ? TextDecoration.lineThrough : null,
                        color: dim ? c.mutedForeground : null,
                      ),
                    ),
                    Wrap(
                      spacing: Space.md,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              line.status.icon,
                              size: 14,
                              color: c.mutedForeground,
                            ),
                            const SizedBox(width: Space.xs),
                            Text(line.status.label, style: text.bodySmall),
                          ],
                        ),
                        if (line.plannedDuration != null)
                          Text(
                            formatDuration(line.plannedDuration!),
                            style: text.bodySmall?.copyWith(
                              fontFamily: 'FiraCode',
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isAdmin) ...[
                IconButton(
                  tooltip: 'Monter',
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: previous == null
                      ? null
                      : () => _run(
                          context,
                          () => repo.swapLines(line.id, previous!.id),
                        ),
                ),
                IconButton(
                  tooltip: 'Descendre',
                  icon: const Icon(Icons.arrow_downward),
                  onPressed: next == null
                      ? null
                      : () => _run(
                          context,
                          () => repo.swapLines(line.id, next!.id),
                        ),
                ),
                PopupMenuButton<LineStatus>(
                  tooltip: 'Statut de la ligne',
                  onSelected: (s) =>
                      _run(context, () => repo.setLineStatus(line.id, s)),
                  itemBuilder: (_) => [
                    for (final s in LineStatus.values)
                      CheckedPopupMenuItem(
                        value: s,
                        checked: s == line.status,
                        child: Text(s.label),
                      ),
                  ],
                ),
              ] else
                Icon(Icons.chevron_right, color: c.mutedForeground),
            ],
          ),
        ),
      ),
    );
  }
}
