import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/data/profile_repository.dart';
import '../data/forum_chat_repository.dart';
import '../domain/forum_post.dart';

/// Forum : l'espace où l'on parle de tout et de rien.
/// Le travail éditorial sérieux (propositions de sujets) se trouve dans « Rédaction ».
class ForumChatScreen extends ConsumerStatefulWidget {
  const ForumChatScreen({super.key});

  @override
  ConsumerState<ForumChatScreen> createState() => _ForumChatScreenState();
}

class _ForumChatScreenState extends ConsumerState<ForumChatScreen> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send(Profile profile) async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(forumChatRepositoryProvider)
          .send(authorId: profile.id, content: text);
      _controller.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Message non envoyé. Vérifiez la connexion et réessayez.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(ForumPost post) async {
    try {
      await ref.read(forumChatRepositoryProvider).delete(post.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Suppression impossible.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final posts = ref.watch(forumPostsProvider);
    final profile = ref.watch(profileProvider).value;
    final names = ref.watch(authorNamesProvider).value ?? const {};
    final c = context.colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Expanded(
            child: posts.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off, size: 40, color: c.mutedForeground),
                    const SizedBox(height: Space.md),
                    Text(
                      'Impossible de charger le forum.',
                      style: TextStyle(color: c.mutedForeground),
                    ),
                    TextButton(
                      onPressed: () => ref.invalidate(forumPostsProvider),
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.forum_outlined,
                          size: 40,
                          color: c.mutedForeground,
                        ),
                        const SizedBox(height: Space.md),
                        Text(
                          'Aucun message pour le moment. Lancez la discussion !',
                          style: TextStyle(color: c.mutedForeground),
                        ),
                      ],
                    ),
                  );
                }
                // Plus récent en bas, comme une conversation.
                return ListView.separated(
                  reverse: true,
                  padding: const EdgeInsets.all(Space.lg),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Space.md),
                  itemBuilder: (_, i) {
                    final post = list[i];
                    final mine =
                        profile != null && post.authorId == profile.id;
                    return _PostCard(
                      post: post,
                      author: post.isSystem
                          ? 'Radio Flow'
                          : (names[post.authorId] ?? 'Auteur inconnu'),
                      canDelete:
                          !post.isSystem &&
                          (mine || (profile?.isAdmin ?? false)),
                      onDelete: () => _delete(post),
                    );
                  },
                );
              },
            ),
          ),
          if (profile != null)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.lg,
                  Space.sm,
                  Space.sm,
                  Space.sm,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Écrire au forum…',
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Envoyer le message',
                      onPressed: _sending ? null : () => _send(profile),
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.post,
    required this.author,
    required this.canDelete,
    required this.onDelete,
  });
  final ForumPost post;
  final String author;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (post.isSystem) ...[
                  Icon(
                    Icons.campaign_outlined,
                    size: 18,
                    color: c.mutedForeground,
                  ),
                  const SizedBox(width: Space.xs),
                ],
                // Auteur et date l'un sous l'autre : pas de débordement à 2x la taille de texte.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(author, style: text.titleSmall),
                      Text(
                        DateFormat('d MMM, HH:mm', 'fr').format(post.createdAt),
                        style: TextStyle(
                          color: c.mutedForeground,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (canDelete)
                  IconButton(
                    tooltip: 'Supprimer le message',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 20),
                  ),
              ],
            ),
            const SizedBox(height: Space.xs),
            Text(post.content),
          ],
        ),
      ),
    );
  }
}
