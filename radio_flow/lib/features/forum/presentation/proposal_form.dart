import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/data/profile_repository.dart';
import '../data/forum_repository.dart';
import '../domain/forum_proposal.dart';

Future<void> showProposalForm(
  BuildContext context,
  WidgetRef ref,
  Profile profile,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => ProposalForm(profile: profile),
  );
}

class ProposalForm extends ConsumerStatefulWidget {
  const ProposalForm({super.key, required this.profile});
  final Profile profile;

  @override
  ConsumerState<ProposalForm> createState() => _ProposalFormState();
}

class _ProposalFormState extends ConsumerState<ProposalForm> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _angle = TextEditingController();
  final _source = TextEditingController();
  ProposalFormat _format = ProposalFormat.article;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _angle.dispose();
    _source.dispose();
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
          .read(forumRepositoryProvider)
          .propose(
            authorId: widget.profile.id,
            title: _title.text,
            angle: _angle.text,
            format: _format,
            source: _source.text,
          );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'La proposition n’a pas pu être envoyée. Réessayez.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _required(String? v, String message) =>
      (v == null || v.trim().isEmpty) ? message : null;

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
                'Proposer un sujet',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: Space.lg),
              TextFormField(
                controller: _title,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Titre du sujet'),
                validator: (v) => _required(v, 'Donnez un titre au sujet.'),
              ),
              const SizedBox(height: Space.lg),
              TextFormField(
                controller: _angle,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Angle',
                  helperText: 'Ce que vous voulez montrer ou expliquer.',
                ),
                validator: (v) => _required(v, 'Précisez l’angle du sujet.'),
              ),
              const SizedBox(height: Space.lg),
              SegmentedButton<ProposalFormat>(
                showSelectedIcon: false,
                segments: [
                  for (final f in ProposalFormat.values)
                    ButtonSegment(
                      value: f,
                      icon: Icon(f.icon),
                      label: Text(f.label),
                    ),
                ],
                selected: {_format},
                onSelectionChanged: (s) => setState(() => _format = s.first),
              ),
              const SizedBox(height: Space.lg),
              TextFormField(
                controller: _source,
                decoration: const InputDecoration(
                  labelText: 'Source (facultatif)',
                ),
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
                    : const Text('Envoyer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
