import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/conductor_repository.dart';
import '../domain/conductor_models.dart';

Future<void> showLineForm(
  BuildContext context,
  WidgetRef ref,
  String conductorId,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => _LineForm(conductorId: conductorId),
  );
}

class _LineForm extends ConsumerStatefulWidget {
  const _LineForm({required this.conductorId});
  final String conductorId;

  @override
  ConsumerState<_LineForm> createState() => _LineFormState();
}

class _LineFormState extends ConsumerState<_LineForm> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _duration = TextEditingController();
  LineItemType _type = LineItemType.reportage;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _duration.dispose();
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
          .read(conductorRepositoryProvider)
          .addLine(
            conductorId: widget.conductorId,
            title: _title.text,
            type: _type,
            plannedDuration: parseDuration(_duration.text),
          );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'La ligne n’a pas pu être ajoutée. Réessayez.');
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
                'Ajouter une ligne',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: Space.lg),
              TextFormField(
                controller: _title,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Titre'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Donnez un titre à la ligne.'
                    : null,
              ),
              const SizedBox(height: Space.lg),
              DropdownButtonFormField<LineItemType>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [
                  for (final t in LineItemType.values)
                    DropdownMenuItem(
                      value: t,
                      child: Row(
                        children: [
                          Icon(t.icon, size: 20),
                          const SizedBox(width: Space.md),
                          Text(t.label),
                        ],
                      ),
                    ),
                ],
                onChanged: (t) => setState(() => _type = t ?? _type),
              ),
              const SizedBox(height: Space.lg),
              TextFormField(
                controller: _duration,
                keyboardType: TextInputType.datetime,
                decoration: const InputDecoration(
                  labelText: 'Durée prévue (facultatif)',
                  helperText: 'Format mm:ss, par exemple 2:30',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty || parseDuration(v) != null)
                    ? null
                    : 'Durée invalide (mm:ss).',
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
                    : const Text('Ajouter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
