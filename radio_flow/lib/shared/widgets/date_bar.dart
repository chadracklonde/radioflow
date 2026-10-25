import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../features/conductor/data/conductor_repository.dart';

/// Barre de navigation par jour, partagée par le Conducteur et l'Espace Son.
class DateBar extends ConsumerWidget {
  const DateBar({super.key, required this.date, this.trailing = const []});

  final DateTime date;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(selectedDateProvider.notifier);
    final label = toBeginningOfSentenceCase(
      DateFormat('EEEE d MMMM', 'fr').format(date),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.sm, Space.sm, Space.sm, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Jour précédent',
            icon: const Icon(Icons.chevron_left),
            onPressed: () =>
                notifier.set(date.subtract(const Duration(days: 1))),
          ),
          Expanded(
            child: TextButton(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(2024),
                  lastDate: DateTime(2100),
                  locale: const Locale('fr'),
                );
                if (picked != null) notifier.set(picked);
              },
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Jour suivant',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => notifier.set(date.add(const Duration(days: 1))),
          ),
          IconButton(
            tooltip: 'Aujourd’hui',
            icon: const Icon(Icons.today),
            onPressed: () => notifier.set(DateTime.now()),
          ),
          ...trailing,
        ],
      ),
    );
  }
}
