import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../data/conductor_repository.dart';

Future<void> showSlotsDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _SlotsDialog());

/// Grille de la station : créneaux utilisés pour générer les conducteurs du jour.
class _SlotsDialog extends ConsumerStatefulWidget {
  const _SlotsDialog();

  @override
  ConsumerState<_SlotsDialog> createState() => _SlotsDialogState();
}

class _SlotsDialogState extends ConsumerState<_SlotsDialog> {
  final _title = TextEditingController();
  TimeOfDay _time = const TimeOfDay(hour: 7, minute: 0);
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  String get _timeText =>
      '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';

  Future<void> _add() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Donnez un nom au créneau (ex. Flash).');
      return;
    }
    try {
      await ref
          .read(conductorRepositoryProvider)
          .addSlot(title: _title.text, time: _timeText);
      _title.clear();
      ref.invalidate(slotsProvider);
      setState(() => _error = null);
    } catch (_) {
      setState(
        () => _error = 'Ce créneau existe déjà ou n’a pas pu être ajouté.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final slots = ref.watch(slotsProvider);
    final c = context.colors;
    return AlertDialog(
      title: const Text('Grille de la station'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              slots.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(Space.lg),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, _) => const Text('Impossible de charger la grille.'),
                data: (list) => list.isEmpty
                    ? Text(
                        'Aucun créneau. Ajoutez par exemple « Flash » à 07:00 et « Journal » à 12:00.',
                        style: TextStyle(color: c.mutedForeground),
                      )
                    : Column(
                        children: [
                          for (final s in list)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Text(
                                s.time,
                                style: const TextStyle(
                                  fontFamily: 'FiraCode',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              title: Text(s.title),
                            ),
                        ],
                      ),
              ),
              const Divider(height: Space.xl),
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Nom du créneau'),
                onSubmitted: (_) => _add(),
              ),
              const SizedBox(height: Space.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.schedule),
                      label: Text('Heure : $_timeText'),
                      onPressed: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: _time,
                        );
                        if (t != null) setState(() => _time = t);
                      },
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  FilledButton(onPressed: _add, child: const Text('Ajouter')),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: Space.sm),
                Text(_error!, style: TextStyle(color: c.danger)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}
