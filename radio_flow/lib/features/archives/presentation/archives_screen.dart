import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/icon_label.dart';
import '../../auth/data/profile_repository.dart';
import '../../conductor/data/conductor_repository.dart';
import '../../sound_space/data/sound_repository.dart';
import '../data/archive_repository.dart';

/// Conducteurs passés, regroupés par jour, avec accès direct à une date.
/// Le rédacteur en chef peut aussi libérer de l'espace en supprimant les sons des éditions
/// diffusées depuis longtemps.
class ArchivesScreen extends ConsumerWidget {
  const ArchivesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final past = ref.watch(pastConductorsProvider);
    final isAdmin = ref.watch(profileProvider).value?.isAdmin ?? false;
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Archives'),
        actions: [
          IconButton(
            tooltip: 'Aller à une date',
            icon: const Icon(Icons.event),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked == null || !context.mounted) return;
              ref.read(selectedDateProvider.notifier).set(picked);
              context.go('/conductor');
            },
          ),
        ],
      ),
      body: past.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Impossible de charger les archives.'),
              TextButton(
                onPressed: () => ref.invalidate(pastConductorsProvider),
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
        data: (list) {
          final children = <Widget>[];
          DateTime? lastDay;
          for (final cond in list) {
            if (lastDay != cond.broadcastDate) {
              lastDay = cond.broadcastDate;
              children.add(
                Padding(
                  padding: const EdgeInsets.only(
                    top: Space.lg,
                    bottom: Space.sm,
                  ),
                  child: Text(
                    DateFormat('EEEE d MMMM yyyy', 'fr').format(lastDay),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              );
            }
            children.add(
              Card(
                child: ListTile(
                  title: Text(cond.title),
                  subtitle: IconLabel(
                    icon: cond.status.icon,
                    label: [
                      if (cond.broadcastTime != null) cond.broadcastTime!,
                      cond.status.label,
                    ].join(' · '),
                    color: c.mutedForeground,
                  ),
                  trailing: Icon(Icons.chevron_right, color: c.mutedForeground),
                  onTap: () {
                    ref
                        .read(selectedDateProvider.notifier)
                        .set(cond.broadcastDate);
                    context.push('/conductor/${cond.id}');
                  },
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(Space.lg),
            children: [
              if (isAdmin) const _CleanupCard(),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(Space.xl),
                  child: Center(
                    child: Text(
                      'Aucun conducteur archivé.',
                      style: TextStyle(color: c.mutedForeground),
                    ),
                  ),
                ),
              ...children,
            ],
          );
        },
      ),
    );
  }
}

/// Suppression des sons des éditions diffusées depuis plus de N jours (rédacteur en chef).
class _CleanupCard extends ConsumerStatefulWidget {
  const _CleanupCard();

  @override
  ConsumerState<_CleanupCard> createState() => _CleanupCardState();
}

class _CleanupCardState extends ConsumerState<_CleanupCard> {
  int _days = 90;
  bool _busy = false;

  Future<void> _run() async {
    final messenger = ScaffoldMessenger.of(context);
    final n = DateTime.now();
    final cutoff = DateTime(
      n.year,
      n.month,
      n.day,
    ).subtract(Duration(days: _days));
    setState(() => _busy = true);
    try {
      final sounds = await ref
          .read(archiveRepositoryProvider)
          .fetchAiredSounds(before: cutoff);
      if (!mounted) return;
      setState(
        () => _busy = false,
      ); // pas de roue qui tourne pendant la confirmation
      if (sounds.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Aucun son à supprimer pour cette période.'),
          ),
        );
        return;
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            'Supprimer ${sounds.length} son${sounds.length > 1 ? 's' : ''} ?',
          ),
          content: Text(
            'Les fichiers audio des éditions diffusées il y a plus de $_days jours seront supprimés définitivement. Les conducteurs, textes et discussions sont conservés. Pensez à télécharger les archives dont vous avez besoin.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer définitivement'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      setState(() => _busy = true);
      final repo = ref.read(soundRepositoryProvider);
      var done = 0;
      for (final s in sounds) {
        try {
          await repo.deleteSound(s);
          done++;
        } catch (_) {}
      }
      ref.invalidate(soundFilesProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            done == sounds.length
                ? '$done son${done > 1 ? 's' : ''} supprimé${done > 1 ? 's' : ''}.'
                : '$done sur ${sounds.length} supprimés. Réessayez pour le reste.',
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Opération impossible. Réessayez.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Libérer de l’espace', style: text.titleSmall),
            const SizedBox(height: Space.xs),
            Text(
              'Supprime les fichiers audio des éditions déjà diffusées.',
              style: text.bodySmall,
            ),
            const SizedBox(height: Space.md),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _days,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Sons de plus de',
                    ),
                    items: const [
                      DropdownMenuItem(value: 30, child: Text('30 jours')),
                      DropdownMenuItem(value: 90, child: Text('90 jours')),
                      DropdownMenuItem(value: 180, child: Text('180 jours')),
                      DropdownMenuItem(value: 365, child: Text('1 an')),
                    ],
                    onChanged: (v) => setState(() => _days = v ?? _days),
                  ),
                ),
                const SizedBox(width: Space.md),
                FilledButton(
                  onPressed: _busy ? null : _run,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Rechercher'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
