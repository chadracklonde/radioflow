import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/local_store.dart';
import '../../data/sync/sync_providers.dart';
import '../../data/sync/sync_service.dart';

/// Bandeau d'état du réseau et de la file d'envoi. Invisible quand tout est à jour.
class SyncBanner extends ConsumerWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider).value;
    if (status == null || status.idle) return const SizedBox.shrink();
    final c = context.colors;

    final IconData icon;
    final String message;
    Color color = c.warning;
    if (status.failed > 0) {
      icon = Icons.error_outline;
      color = c.danger;
      message =
          '${status.failed} modification${status.failed > 1 ? 's' : ''} refusée${status.failed > 1 ? 's' : ''} par le serveur';
    } else if (!status.online) {
      icon = Icons.cloud_off;
      message = status.pending == 0
          ? 'Hors ligne : vos prochaines modifications seront envoyées au retour du réseau.'
          : 'Hors ligne : ${status.pending} modification${status.pending > 1 ? 's' : ''} en attente d’envoi.';
    } else {
      icon = Icons.sync;
      message =
          'Synchronisation en cours : ${status.pending} modification${status.pending > 1 ? 's' : ''} à envoyer.';
    }

    return Semantics(
      liveRegion: true,
      container: true,
      child: Material(
        color: c.muted,
        child: InkWell(
          onTap: status.failed > 0 ? () => _showFailed(context, ref) : null,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: color, width: 2)),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: Space.lg,
              vertical: Space.sm,
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    message,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: c.foreground),
                  ),
                ),
                if (status.failed > 0)
                  Text(
                    'Voir',
                    style: TextStyle(color: color, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showFailed(BuildContext context, WidgetRef ref) {
    final store = ref.read(localStoreProvider);
    final sync = ref.read(syncServiceProvider);
    return showDialog<void>(
      context: context,
      builder: (_) => FutureBuilder<List<OutboxItem>>(
        future: store.items(),
        builder: (context, snap) {
          final failed = (snap.data ?? const <OutboxItem>[])
              .where((i) => i.failed)
              .toList();
          return AlertDialog(
            title: const Text('Modifications refusées'),
            content: SizedBox(
              width: 420,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final i in failed)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(_label(i)),
                      subtitle: Text(
                        i.error ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await store.discardFailed();
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Supprimer'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await sync.retryFailed();
                },
                child: const Text('Réessayer'),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _label(OutboxItem i) => switch (i.kind) {
    'forum.propose' => 'Proposition de sujet : ${i.payload['title']}',
    'task.add' => 'Nouvelle tâche : ${i.payload['title']}',
    'task.setStatus' => 'Changement de statut d’une tâche',
    'task.delete' => 'Suppression d’une tâche',
    'thread.sendText' => 'Message : ${i.payload['text']}',
    _ => i.kind,
  };
}

/// Petite pastille « en attente d'envoi » pour les éléments rédigés hors ligne.
class PendingSyncTag extends StatelessWidget {
  const PendingSyncTag({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.cloud_upload_outlined, size: 14, color: c.warning),
        const SizedBox(width: Space.xs),
        Text(
          'En attente d’envoi',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: c.warning),
        ),
      ],
    );
  }
}

/// Utilisé par les tests : affiche l'état courant de la synchronisation.
String describeSync(SyncStatus s) =>
    'online=${s.online} pending=${s.pending} failed=${s.failed}';
