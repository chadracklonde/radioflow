import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/data/profile_repository.dart';
import '../data/forum_repository.dart';
import '../domain/forum_proposal.dart';
import '../../../shared/widgets/sync_banner.dart';
import 'proposal_form.dart';

class ForumScreen extends ConsumerStatefulWidget {
  const ForumScreen({super.key});

  @override
  ConsumerState<ForumScreen> createState() => _ForumScreenState();
}

class _ForumScreenState extends ConsumerState<ForumScreen> {
  ProposalStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final proposals = ref.watch(forumProposalsProvider);
    final profile = ref.watch(profileProvider).value;
    final names = ref.watch(authorNamesProvider).value ?? const {};

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: (profile?.canPropose ?? false)
          ? FloatingActionButton.extended(
              onPressed: () => showProposalForm(context, ref, profile!),
              icon: const Icon(Icons.add),
              label: const Text('Proposer un sujet'),
            )
          : null,
      body: Column(
        children: [
          SizedBox(
            height: 64,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: Space.lg,
                vertical: Space.sm,
              ),
              children: [
                _FilterChip(
                  label: 'Tous',
                  selected: _filter == null,
                  onTap: () => setState(() => _filter = null),
                ),
                for (final s in ProposalStatus.values)
                  _FilterChip(
                    label: s.label,
                    selected: _filter == s,
                    onTap: () => setState(() => _filter = s),
                  ),
              ],
            ),
          ),
          Expanded(
            child: proposals.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _Message(
                icon: Icons.cloud_off,
                text: 'Impossible de charger le forum.',
                action: TextButton(
                  onPressed: () => ref.invalidate(forumProposalsProvider),
                  child: const Text('Réessayer'),
                ),
              ),
              data: (all) {
                final list = _filter == null
                    ? all
                    : all.where((p) => p.status == _filter).toList();
                if (list.isEmpty) {
                  return _Message(
                    icon: Icons.forum_outlined,
                    text: all.isEmpty
                        ? 'Aucune proposition pour le moment.'
                        : 'Aucune proposition dans cette catégorie.',
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
                  separatorBuilder: (_, _) => const SizedBox(height: Space.md),
                  itemBuilder: (_, i) => _ProposalCard(
                    proposal: list[i],
                    author: names[list[i].authorId] ?? 'Auteur inconnu',
                    isAdmin: profile?.isAdmin ?? false,
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

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: Space.sm),
    child: ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      materialTapTargetSize: MaterialTapTargetSize.padded,
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 40, color: context.colors.mutedForeground),
        const SizedBox(height: Space.md),
        Text(text, style: TextStyle(color: context.colors.mutedForeground)),
        ?action,
      ],
    ),
  );
}

class _ProposalCard extends ConsumerWidget {
  const _ProposalCard({
    required this.proposal,
    required this.author,
    required this.isAdmin,
  });
  final ForumProposal proposal;
  final String author;
  final bool isAdmin;

  Color _statusColor(AppColors c) => switch (proposal.status) {
    ProposalStatus.approved => c.success,
    ProposalStatus.rejected => c.danger,
    ProposalStatus.changesRequested || ProposalStatus.pending => c.warning,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final statusColor = _statusColor(c);
    final open =
        proposal.status == ProposalStatus.pending ||
        proposal.status == ProposalStatus.changesRequested;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(proposal.title, style: text.titleMedium)),
                const SizedBox(width: Space.sm),
                // Statut : icône + libellé, jamais la couleur seule.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(proposal.status.icon, size: 18, color: statusColor),
                    const SizedBox(width: Space.xs),
                    Text(
                      proposal.status.label,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (proposal.pendingSync) ...[
              const SizedBox(height: Space.xs),
              const PendingSyncTag(),
            ],
            const SizedBox(height: Space.sm),
            Text(proposal.angle, style: text.bodyMedium),
            const SizedBox(height: Space.md),
            Wrap(
              spacing: Space.md,
              runSpacing: Space.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Meta(icon: proposal.format.icon, label: proposal.format.label),
                _Meta(icon: Icons.person_outline, label: author),
                _Meta(
                  icon: Icons.schedule,
                  label: DateFormat(
                    'd MMM, HH:mm',
                    'fr',
                  ).format(proposal.createdAt.toLocal()),
                ),
                if (proposal.source != null)
                  _Meta(icon: Icons.link, label: proposal.source!),
              ],
            ),
            if (proposal.decisionNote != null) ...[
              const SizedBox(height: Space.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Space.md),
                decoration: BoxDecoration(
                  color: c.muted,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Note du rédacteur en chef : ${proposal.decisionNote}',
                  style: text.bodySmall?.copyWith(color: c.foreground),
                ),
              ),
            ],
            if (proposal.status == ProposalStatus.approved) ...[
              const SizedBox(height: Space.md),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/forum/${proposal.id}/thread'),
                  icon: const Icon(Icons.forum_outlined),
                  label: const Text('Ouvrir la discussion'),
                ),
              ),
            ],
            if (isAdmin && open) ...[
              const SizedBox(height: Space.md),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  FilledButton.icon(
                    onPressed: () => _decide(
                      context,
                      ref,
                      ProposalStatus.approved,
                      askNote: false,
                    ),
                    icon: const Icon(Icons.check),
                    label: const Text('Valider'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () =>
                        _decide(context, ref, ProposalStatus.changesRequested),
                    icon: const Icon(Icons.edit_note),
                    label: const Text('À revoir'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () =>
                        _decide(context, ref, ProposalStatus.rejected),
                    icon: Icon(Icons.close, color: c.danger),
                    label: const Text('Refuser'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    ProposalStatus status, {
    bool askNote = true,
  }) async {
    String? note;
    if (askNote) {
      note = await showDialog<String>(
        context: context,
        builder: (_) => _NoteDialog(status: status),
      );
      if (note == null) return; // annulé
    }
    try {
      await ref
          .read(forumRepositoryProvider)
          .decide(proposal.id, status, note: note);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La décision n’a pas pu être enregistrée. Réessayez.',
            ),
          ),
        );
      }
    }
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: c.mutedForeground),
        const SizedBox(width: Space.xs),
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.status});
  final ProposalStatus status;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.status == ProposalStatus.rejected
        ? 'Refuser la proposition'
        : 'Demander des modifications';
    return AlertDialog(
      title: Text(title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Note pour le journaliste (facultative)',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Confirmer'),
        ),
      ],
    );
  }
}
