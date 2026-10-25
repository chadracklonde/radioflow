import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/data/profile_repository.dart';
import '../data/tasks_repository.dart';

Future<void> showTaskForm(BuildContext context, Profile profile) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => _TaskForm(profile: profile),
  );
}

class _TaskForm extends ConsumerStatefulWidget {
  const _TaskForm({required this.profile});
  final Profile profile;

  @override
  ConsumerState<_TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends ConsumerState<_TaskForm> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  DateTime? _due;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(tasksRepositoryProvider)
          .add(userId: widget.profile.id, title: _title.text, dueDate: _due);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'La tâche n’a pas pu être créée. Réessayez.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.lg,
        0,
        Space.lg,
        Space.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Nouvelle tâche',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: Space.lg),
              TextFormField(
                controller: _title,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Tâche',
                  helperText: 'Ex. Monter le reportage du marché',
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Décrivez la tâche.'
                    : null,
              ),
              const SizedBox(height: Space.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event),
                      label: Text(
                        _due == null
                            ? 'Échéance (facultatif)'
                            : DateFormat('EEEE d MMMM', 'fr').format(_due!),
                      ),
                      onPressed: () async {
                        final now = DateTime.now();
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _due ?? now,
                          firstDate: DateTime(now.year - 1),
                          lastDate: DateTime(now.year + 2),
                          locale: const Locale('fr'),
                        );
                        if (d != null) setState(() => _due = d);
                      },
                    ),
                  ),
                  if (_due != null)
                    IconButton(
                      tooltip: 'Retirer l’échéance',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _due = null),
                    ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: Space.md),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: Space.xl),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Text('Créer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
