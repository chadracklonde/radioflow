import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/data/profile_repository.dart';
import '../data/tasks_repository.dart';
import '../domain/task_models.dart';
import '../../../shared/widgets/sync_banner.dart';
import '../../../shared/widgets/icon_label.dart';
import 'task_form.dart';

/// Tâches de toute l'équipe : chacun gère les siennes, tout le monde voit tout.
class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  bool _showDone = false;
  bool _onlyMine = false;

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(tasksProvider);
    final profile = ref.watch(profileProvider).value;
    final names = ref.watch(authorNamesProvider).value ?? const {};
    final c = context.colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: profile == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showTaskForm(context, profile),
              icon: const Icon(Icons.add),
              label: const Text('Nouvelle tâche'),
            ),
      body: Column(
        children: [
          Padding(
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
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('En cours')),
                    ButtonSegment(value: true, label: Text('Terminées')),
                  ],
                  selected: {_showDone},
                  onSelectionChanged: (s) =>
                      setState(() => _showDone = s.first),
                ),
                FilterChip(
                  label: const Text('Mes tâches'),
                  selected: _onlyMine,
                  onSelected: (v) => setState(() => _onlyMine = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: tasks.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off, size: 40, color: c.mutedForeground),
                    const SizedBox(height: Space.md),
                    const Text('Impossible de charger les tâches.'),
                    TextButton(
                      onPressed: () => ref.invalidate(tasksProvider),
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
              data: (all) {
                final list = all
                    .where((t) => t.isDone == _showDone)
                    .where((t) => !_onlyMine || t.userId == profile?.id)
                    .toList();
                if (list.isEmpty) {
                  return Center(
                    child: Text(
                      _showDone
                          ? 'Aucune tâche terminée.'
                          : 'Aucune tâche en cours.',
                      style: TextStyle(color: c.mutedForeground),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    Space.sm,
                    Space.lg,
                    96,
                  ),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
                  itemBuilder: (_, i) => _TaskCard(
                    task: list[i],
                    owner: names[list[i].userId] ?? 'Membre',
                    canEdit:
                        profile != null &&
                        (profile.isAdmin || profile.id == list[i].userId),
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

class _TaskCard extends ConsumerWidget {
  const _TaskCard({
    required this.task,
    required this.owner,
    required this.canEdit,
  });
  final TeamTask task;
  final String owner;
  final bool canEdit;

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
    final repo = ref.read(tasksRepositoryProvider);
    final overdue = task.isOverdue(DateTime.now());
    final statusRow = IconLabel(
      icon: task.status.icon,
      label: task.status.label,
      color: task.isDone ? c.success : c.mutedForeground,
      style: text.bodySmall?.copyWith(color: c.foreground),
      trailing: canEdit
          ? Icon(Icons.arrow_drop_down, size: 18, color: c.mutedForeground)
          : null,
    );
    final status = canEdit
        ? PopupMenuButton<TaskStatus>(
            tooltip: 'Changer le statut',
            onSelected: (s) => _run(context, () => repo.setStatus(task.id, s)),
            itemBuilder: (_) => [
              for (final s in TaskStatus.values)
                CheckedPopupMenuItem(
                  value: s,
                  checked: s == task.status,
                  child: Text(s.label),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.sm),
              child: statusRow,
            ),
          )
        : statusRow;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    task.title,
                    style: text.bodyLarge?.copyWith(
                      decoration: task.isDone
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
                if (canEdit)
                  IconButton(
                    tooltip: 'Supprimer la tâche',
                    icon: Icon(Icons.delete_outline, color: c.mutedForeground),
                    onPressed: () => _run(context, () => repo.delete(task.id)),
                  ),
              ],
            ),
            if (task.pendingSync) ...[
              const SizedBox(height: Space.xs),
              const PendingSyncTag(),
            ],
            Wrap(
              spacing: Space.lg,
              runSpacing: Space.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                status,
                IconLabel(
                  icon: Icons.person_outline,
                  label: owner,
                  color: c.mutedForeground,
                ),
                if (task.dueDate != null)
                  IconLabel(
                    icon: overdue ? Icons.warning_amber : Icons.event,
                    label:
                        '${overdue ? 'En retard : ' : ''}${DateFormat('d MMM', 'fr').format(task.dueDate!)}',
                    color: overdue ? c.danger : c.mutedForeground,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
