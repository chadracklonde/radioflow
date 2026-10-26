import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../forum/data/forum_repository.dart';
import '../../forum/domain/forum_proposal.dart';
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
  String? _proposalId;
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
      final lineId = await ref
          .read(conductorRepositoryProvider)
          .addLine(
            conductorId: widget.conductorId,
            title: _title.text,
            type: _type,
            plannedDuration: parseDuration(_duration.text),
          );
      // Sujet validé choisi : son fil de discussion devient celui de la ligne.
      final proposalId = _proposalId;
      if (proposalId != null) {
        try {
          await ref
              .read(forumRepositoryProvider)
              .linkToLine(proposalId, lineId);
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Ligne ajoutée, mais le sujet n\u2019a pas pu y être lié. Réessayez depuis le Forum.',
                ),
              ),
            );
          }
        }
      }
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
              Builder(
                builder: (context) {
                  final candidates =
                      (ref.watch(forumProposalsProvider).value ??
                              const <ForumProposal>[])
                          .where(
                            (p) =>
                                p.status == ProposalStatus.approved &&
                                p.conductorLineId == null,
                          )
                          .toList();
                  if (candidates.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: Space.lg),
                    child: DropdownButtonFormField<String?>(
                      initialValue: _proposalId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Sujet validé (facultatif)',
                        helperText: 'Sa discussion devient celle de la ligne, rien n\u2019est perdu.',
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Aucun'),
                        ),
                        for (final p in candidates)
                          DropdownMenuItem<String?>(
                            value: p.id,
                            child: Text(
                              p.title,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (id) => setState(() {
                        _proposalId = id;
                        if (id != null && _title.text.trim().isEmpty) {
                          _title.text = candidates
                              .firstWhere((p) => p.id == id)
                              .title;
                        }
                      }),
                    ),
                  );
                },
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
