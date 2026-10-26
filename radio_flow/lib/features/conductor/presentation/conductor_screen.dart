import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/data/profile_repository.dart';
import '../../../shared/widgets/date_bar.dart';
import '../data/conductor_repository.dart';
import '../domain/conductor_models.dart';
import '../../../shared/widgets/icon_label.dart';
import 'slots_dialog.dart';

/// Conducteurs d'une journée, avec navigation de date.
class ConductorScreen extends ConsumerWidget {
  const ConductorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(selectedDateProvider);
    final conductors = ref.watch(conductorsProvider(isoDate(date)));
    final profile = ref.watch(profileProvider).value;
    final isAdmin = profile?.isAdmin ?? false;
    final c = context.colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          DateBar(
            date: date,
            trailing: [
              if (isAdmin)
                IconButton(
                  tooltip: 'Générer les conducteurs manquants',
                  icon: const Icon(Icons.auto_awesome),
                  onPressed: () => generateForDate(context, ref, date),
                ),
              if (isAdmin)
                IconButton(
                  tooltip: 'Grille de la station',
                  icon: const Icon(Icons.calendar_view_week),
                  onPressed: () => showSlotsDialog(context),
                ),
            ],
          ),
          Expanded(
            child: conductors.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off, size: 40, color: c.mutedForeground),
                    const SizedBox(height: Space.md),
                    const Text('Impossible de charger les conducteurs.'),
                    TextButton(
                      onPressed: () =>
                          ref.invalidate(conductorsProvider(isoDate(date))),
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
              data: (list) {
                if (list.isEmpty) return _Empty(date: date, isAdmin: isAdmin);
                return ListView.separated(
                  padding: const EdgeInsets.all(Space.lg),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Space.md),
                  itemBuilder: (_, i) => _ConductorCard(conductor: list[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Crée les conducteurs manquants du jour d'après la grille et dit clairement ce qui s'est passé.
Future<void> generateForDate(
  BuildContext context,
  WidgetRef ref,
  DateTime date,
) async {
  final messenger = ScaffoldMessenger.of(context);
  String message;
  try {
    final n = await ref.read(conductorRepositoryProvider).generate(date);
    message = n == 0
        ? 'Rien à créer : tous les créneaux de la grille existent déjà pour ce jour, ou aucun ne correspond.'
        : '$n conducteur${n > 1 ? 's' : ''} créé${n > 1 ? 's' : ''}.';
  } catch (_) {
    message = 'La génération a échoué. Vérifiez la connexion et réessayez.';
  }
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

const _dayNames = [
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];

class _Empty extends ConsumerStatefulWidget {
  const _Empty({required this.date, required this.isAdmin});
  final DateTime date;
  final bool isAdmin;

  @override
  ConsumerState<_Empty> createState() => _EmptyState();
}

class _EmptyState extends ConsumerState<_Empty> {
  bool _busy = false;

  Future<void> _generate() async {
    setState(() => _busy = true);
    await generateForDate(context, ref, widget.date);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final muted = TextStyle(color: c.mutedForeground);
    final slots = ref.watch(slotsProvider);
    final day = _dayNames[widget.date.weekday - 1];

    String? guidance;
    var needsGrid = false;
    if (widget.isAdmin) {
      final list = slots.value;
      if (list != null && list.isEmpty) {
        guidance = 'La grille de la station est vide : ajoutez vos créneaux (ex. Flash de 07h, Journal de 12h) pour pouvoir générer les conducteurs.';
        needsGrid = true;
      } else if (list != null && !list.any((s) => s.airsOn(widget.date))) {
        guidance = 'Aucun créneau de la grille n’est prévu le $day.';
        needsGrid = true;
      }
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.view_list_outlined, size: 40, color: c.mutedForeground),
            const SizedBox(height: Space.md),
            Text('Aucun conducteur ce jour-là.', style: muted),
            if (!widget.isAdmin) ...[
              const SizedBox(height: Space.sm),
              Text(
                'Le rédacteur en chef les génère d’après la grille de la station.',
                textAlign: TextAlign.center,
                style: muted,
              ),
            ],
            if (guidance != null) ...[
              const SizedBox(height: Space.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(
                  guidance,
                  textAlign: TextAlign.center,
                  style: muted,
                ),
              ),
            ],
            if (widget.isAdmin) ...[
              const SizedBox(height: Space.lg),
              if (needsGrid)
                FilledButton.icon(
                  onPressed: () => showSlotsDialog(context),
                  icon: const Icon(Icons.calendar_view_week),
                  label: const Text('Configurer la grille'),
                )
              else
                FilledButton.icon(
                  onPressed: _busy ? null : _generate,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: const Text('Générer d’après la grille'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConductorCard extends StatelessWidget {
  const _ConductorCard({required this.conductor});
  final Conductor conductor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final locked = conductor.status.isLocked;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/conductor/${conductor.id}'),
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Row(
            children: [
              if (conductor.broadcastTime != null) ...[
                Text(
                  conductor.broadcastTime!,
                  style: text.titleLarge?.copyWith(
                    fontFamily: 'FiraCode',
                    color: c.success,
                  ),
                ),
                const SizedBox(width: Space.lg),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(conductor.title, style: text.titleMedium),
                    const SizedBox(height: Space.xs),
                    IconLabel(
                      icon: conductor.status.icon,
                      label: conductor.status.label,
                      color: locked ? c.warning : c.mutedForeground,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.sm),
              Icon(Icons.chevron_right, color: c.mutedForeground),
            ],
          ),
        ),
      ),
    );
  }
}
