import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/data/profile_repository.dart';
import '../../../core/utils/file_saver.dart';
import '../../sound_space/data/sound_repository.dart';
import '../data/conductor_export.dart';
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

  /// Durée du son le plus récent de chaque ligne de ce conducteur.
  Map<String, int> _soundSeconds(WidgetRef ref) {
    final files = ref.watch(soundFilesProvider(date)).value ?? const [];
    final sorted = [...files.where((f) => f.conductorId == conductorId)]
      ..sort((a, b) => a.uploadedAt.compareTo(b.uploadedAt));
    return {
      for (final f in sorted)
        if (f.duration != null) f.lineId: f.duration!,
    };
  }

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
    final sounds = _soundSeconds(ref);

    Future<void> export() async {
      final messenger = ScaffoldMessenger.of(context);
      final list = lines.value;
      if (conductor == null || list == null) return;
      try {
        final bytes = await buildConductorPdf(conductor, list, sounds);
        final name = conductorExportName(conductor);
        final saved = await ref
            .read(fileSaverProvider)
            .save(fileName: name, bytes: bytes, mimeType: 'application/pdf');
        if (saved) {
          messenger.showSnackBar(SnackBar(content: Text('$name enregistré.')));
        }
      } catch (_) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Export impossible. Réessayez.')),
        );
      }
    }

    Future<void> saveTemplate() async {
      final messenger = ScaffoldMessenger.of(context);
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Enregistrer comme modèle ?'),
          content: const Text(
            'Les lignes de ce conducteur (hors abandonnées) deviendront les lignes de départ de toutes les prochaines éditions de ce créneau. Le modèle précédent est remplacé.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      try {
        final n = await repo.saveAsTemplate(conductorId);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Modèle enregistré : $n ligne${n > 1 ? 's' : ''}.'),
          ),
        );
      } catch (_) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Enregistrement impossible.')),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(conductor?.title ?? 'Conducteur'),
        actions: [
          IconButton(
            tooltip: 'Historique des modifications',
            icon: const Icon(Icons.history),
            onPressed: () => showHistorySheet(context, conductorId),
          ),
          if (isAdmin && conductor?.slotId != null)
            IconButton(
              tooltip: 'Enregistrer comme modèle du créneau',
              icon: const Icon(Icons.bookmark_add_outlined),
              onPressed: () => saveTemplate(),
            ),
          IconButton(
            tooltip: 'Exporter en PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: conductor == null || lines.value == null ? null : export,
          ),
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
          if (lines.value != null && lines.value!.isNotEmpty)
            _TimingBar(
              timing: ConductorTiming.compute(lines.value!, sounds),
              target: conductor?.targetDuration,
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
                    soundSeconds: sounds[list[i].id],
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

class _TimingBar extends StatelessWidget {
  const _TimingBar({required this.timing, this.target});
  final ConductorTiming timing;
  final int? target;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      color: c.muted,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.sm,
      ),
      child: Wrap(
        spacing: Space.lg,
        runSpacing: Space.xs,
        children: [
          Text(
            'Prévu ${formatDuration(timing.planned)}',
            style: text.bodyMedium?.copyWith(fontFamily: 'FiraCode'),
          ),
          Text(
            'Estimé ${formatDuration(timing.estimated)}',
            style: text.bodyMedium?.copyWith(
              fontFamily: 'FiraCode',
              fontWeight: FontWeight.w600,
            ),
          ),
          if (target != null)
            Text(
              'Cible ${formatDuration(target!)}',
              style: text.bodyMedium?.copyWith(fontFamily: 'FiraCode'),
            ),
          if (target != null)
            Builder(
              builder: (_) {
                final diff = timing.estimated - target!;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      diff > 0
                          ? Icons.warning_amber
                          : Icons.check_circle_outline,
                      size: 16,
                      color: diff > 0 ? c.warning : c.success,
                    ),
                    const SizedBox(width: Space.xs),
                    Text(
                      diff > 0
                          ? 'Dépassement de ${formatDuration(diff)}'
                          : diff == 0
                          ? 'Durée exacte'
                          : 'Reste ${formatDuration(-diff)}',
                      style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                );
              },
            ),
          Text(
            '${timing.withSound}/${timing.counted} lignes avec son',
            style: text.bodySmall,
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
    this.soundSeconds,
  });

  final int? soundSeconds;
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
                        if (soundSeconds != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.audiotrack,
                                size: 14,
                                color: c.success,
                              ),
                              const SizedBox(width: Space.xs),
                              Text(
                                formatDuration(soundSeconds!),
                                style: text.bodySmall?.copyWith(
                                  fontFamily: 'FiraCode',
                                ),
                              ),
                            ],
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

/// Historique des modifications du conducteur (qui a fait quoi, quand).
Future<void> showHistorySheet(BuildContext context, String conductorId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => _HistorySheet(conductorId: conductorId),
  );
}

class _HistorySheet extends ConsumerWidget {
  const _HistorySheet({required this.conductorId});
  final String conductorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider(conductorId));
    final names = ref.watch(authorNamesProvider).value ?? const {};
    final c = context.colors;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
            child: Text(
              'Historique des modifications',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Expanded(
            child: history.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const Center(
                child: Text('Impossible de charger l’historique.'),
              ),
              data: (list) => list.isEmpty
                  ? Center(
                      child: Text(
                        'Aucune modification enregistrée.',
                        style: TextStyle(color: c.mutedForeground),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(Space.lg),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final e = list[i];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(e.summary),
                          subtitle: Text(
                            '${names[e.userId] ?? 'Système'} · ${DateFormat('dd/MM HH:mm').format(e.createdAt.toLocal())}',
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
