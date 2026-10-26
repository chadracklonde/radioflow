import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/data/profile_repository.dart';
import '../../conductor/data/conductor_repository.dart';
import '../../conductor/domain/conductor_models.dart';
import '../../sound_space/data/audio_services.dart';
import '../../sound_space/data/sound_repository.dart';
import '../../../core/utils/audio_naming.dart';
import '../../../shared/widgets/sync_banner.dart';
import '../../forum/data/forum_repository.dart';
import '../data/thread_repository.dart';
import '../domain/thread_message.dart';

/// Fil de discussion (style Teams), ouvert à toute l'équipe :
/// - d'une ligne du conducteur (`conductorId` + `lineId`), avec envoi de sons;
/// - d'un sujet validé (`proposalId`), dès la validation : texte pour tous, et les sons
///   s'envoient depuis la ligne une fois le sujet placé dans un conducteur.
/// Aucun statut ne désactive la saisie : seul le verrouillage d'un conducteur ferme l'envoi de sons.
class ThreadScreen extends ConsumerStatefulWidget {
  const ThreadScreen({
    super.key,
    this.conductorId,
    this.lineId,
    this.proposalId,
  }) : assert(
         (proposalId != null) != (lineId != null && conductorId != null),
         'Un fil se rattache soit à une ligne du conducteur, soit à un sujet',
       );

  final String? conductorId;
  final String? lineId;
  final String? proposalId;

  @override
  ConsumerState<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends ConsumerState<ThreadScreen> {
  final _controller = TextEditingController();
  bool _sending = false;
  bool _uploading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send(String threadId, String userId) async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(threadRepositoryProvider)
          .sendText(threadId: threadId, userId: userId, text: text);
      _controller.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message non envoyé. Réessayez.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _upload({
    required String threadId,
    required String userId,
    required Conductor conductor,
    required ConductorLine line,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final files = ref.read(audioFileServiceProvider);
    final picked = await files.pick();
    if (picked == null) return;
    final problem = AudioRules.validate(name: picked.name, size: picked.size);
    if (problem != null) {
      messenger.showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    setState(() => _uploading = true);
    try {
      final stored = await ref
          .read(soundRepositoryProvider)
          .upload(
            conductorId: conductor.id,
            threadId: threadId,
            userId: userId,
            position: line.position,
            date: conductor.broadcastDate,
            originalName: picked.name,
            bytes: await picked.readBytes(),
          );
      messenger.showSnackBar(
        SnackBar(content: Text('Envoyé sous le nom $stored')),
      );
    } on DuplicateAudioException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Un fichier ${e.name} existe déjà dans cette édition.'),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Envoi impossible (droits, conducteur verrouillé ou réseau). Réessayez.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isProposal = widget.proposalId != null;
    final line = isProposal
        ? null
        : ref
              .watch(linesProvider(widget.conductorId!))
              .value
              ?.where((l) => l.id == widget.lineId)
              .firstOrNull;
    final proposal = !isProposal
        ? null
        : ref
              .watch(forumProposalsProvider)
              .value
              ?.where((p) => p.id == widget.proposalId)
              .firstOrNull;
    final threadId = isProposal
        ? ref.watch(proposalThreadIdProvider(widget.proposalId!))
        : ref.watch(threadIdProvider(widget.lineId!));
    final profile = ref.watch(profileProvider).value;
    final names = ref.watch(authorNamesProvider).value ?? const {};
    final c = context.colors;
    final conductor = isProposal
        ? null
        : ref
              .watch(
                conductorsProvider(isoDate(ref.watch(selectedDateProvider))),
              )
              .value
              ?.where((x) => x.id == widget.conductorId)
              .firstOrNull;
    final canUpload =
        profile != null &&
        profile.canPropose &&
        conductor != null &&
        line != null &&
        (profile.isAdmin || !conductor.status.isLocked);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isProposal
              ? (proposal?.title ?? 'Discussion du sujet')
              : (line?.title ?? 'Fil de discussion'),
        ),
      ),
      body: threadId.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Fil de discussion introuvable.')),
        data: (tid) {
          final messages = ref.watch(messagesProvider(tid));
          return Column(
            children: [
              if (isProposal)
                _ProposalHint(placed: proposal?.conductorLineId != null),
              Expanded(
                child: messages.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => const Center(
                    child: Text('Impossible de charger les messages.'),
                  ),
                  data: (list) {
                    if (list.isEmpty) {
                      return Center(
                        child: Text(
                          'Aucun message. Lancez la discussion.',
                          style: TextStyle(color: c.mutedForeground),
                        ),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.all(Space.lg),
                      itemCount: list.length,
                      itemBuilder: (_, i) => _MessageBubble(
                        message: list[i],
                        author: names[list[i].userId] ?? 'Membre',
                        mine: list[i].userId == profile?.id,
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  decoration: BoxDecoration(
                    color: c.card,
                    border: Border(top: BorderSide(color: c.divider)),
                  ),
                  padding: const EdgeInsets.all(Space.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (canUpload)
                        IconButton(
                          tooltip: 'Envoyer un fichier audio',
                          onPressed: _uploading
                              ? null
                              : () => _upload(
                                  threadId: tid,
                                  userId: profile.id,
                                  conductor: conductor,
                                  line: line,
                                ),
                          icon: _uploading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Icon(Icons.attach_file),
                        ),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.newline,
                          decoration: const InputDecoration(
                            hintText: 'Écrire un message',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      IconButton.filled(
                        tooltip: 'Envoyer',
                        onPressed: (_sending || profile == null)
                            ? null
                            : () => _send(tid, profile.id),
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.author,
    required this.mine,
  });
  final ThreadMessage message;
  final String author;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: Space.md),
        padding: const EdgeInsets.all(Space.md),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: mine ? c.success.withValues(alpha: 0.16) : c.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$author · ${DateFormat('d MMM HH:mm', 'fr').format(message.createdAt.toLocal())}',
              style: text.bodySmall,
            ),
            if (message.pendingSync) ...[
              const SizedBox(height: Space.xs),
              const PendingSyncTag(),
            ],
            if (message.content != null) ...[
              const SizedBox(height: Space.xs),
              Text(message.content!, style: text.bodyMedium),
            ],
            if (message.hasAudio) ...[
              const SizedBox(height: Space.sm),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.audiotrack, size: 18, color: c.success),
                  const SizedBox(width: Space.sm),
                  Flexible(
                    child: Text(
                      message.audioName ?? 'Fichier audio',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (message.audioDuration != null) ...[
                    const SizedBox(width: Space.sm),
                    Text(
                      formatDuration(message.audioDuration!),
                      style: text.bodySmall?.copyWith(fontFamily: 'FiraCode'),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Rappel en tête du fil d'un sujet : le texte est libre, les sons suivent le conducteur.
class _ProposalHint extends StatelessWidget {
  const _ProposalHint({required this.placed});
  final bool placed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      color: c.muted,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(Icons.forum_outlined, size: 18, color: c.success),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              placed
                  ? 'Ce sujet est placé dans un conducteur : les sons s\u2019envoient depuis sa ligne.'
                  : 'Sujet validé : toute l\u2019équipe peut écrire ici. Les sons s\u2019enverront depuis le conducteur, une fois le sujet placé.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: c.foreground),
            ),
          ),
        ],
      ),
    );
  }
}
