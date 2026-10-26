import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../data/notification_repository.dart';

/// Cloche de la coque : icône avec le nombre de notifications non lues.
class NotificationsBell extends ConsumerWidget {
  const NotificationsBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider);
    return IconButton(
      tooltip: unread == 0
          ? 'Notifications'
          : 'Notifications ($unread non lue${unread > 1 ? 's' : ''})',
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: Icon(
          unread > 0 ? Icons.notifications : Icons.notifications_none,
        ),
      ),
      onPressed: () => context.push('/notifications'),
    );
  }
}

IconData _icon(String kind) => switch (kind) {
  'proposal.new' => Icons.lightbulb_outline,
  'proposal.approved' => Icons.check_circle_outline,
  'proposal.rejected' => Icons.cancel_outlined,
  'sound.new' => Icons.audiotrack,
  _ => Icons.notifications_none,
};

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  /// Identifiants non lus à l'ouverture : ils restent mis en évidence pendant la visite.
  Set<String>? _freshIds;
  bool _marked = false;

  Future<void> _markRead() async {
    if (_marked) return;
    _marked = true;
    try {
      await ref.read(notificationRepositoryProvider).markAllRead();
    } catch (_) {
      _marked = false; // nouvelle tentative à la prochaine mise à jour
    }
  }

  void _open(AppNotification n) {
    switch (n.refType) {
      case 'proposal':
        context.go('/forum');
      case 'message':
        context.go('/sound');
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(notificationsProvider);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Text('Impossible de charger les notifications.'),
        ),
        data: (items) {
          _freshIds ??= {for (final n in items.where((n) => n.unread)) n.id};
          if (items.any((n) => n.unread)) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
          }
          if (items.isEmpty) {
            return Center(
              child: Text(
                'Aucune notification pour le moment.',
                style: TextStyle(color: c.mutedForeground),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(Space.lg),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
            itemBuilder: (_, i) {
              final n = items[i];
              final fresh = _freshIds!.contains(n.id);
              return Card(
                child: ListTile(
                  leading: Icon(_icon(n.kind), color: c.success),
                  title: Text(
                    n.title,
                    style: text.bodyLarge?.copyWith(
                      fontWeight: fresh ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                  subtitle: Text(
                    '${n.body ?? ''}${n.body != null ? ' · ' : ''}${DateFormat('dd/MM HH:mm').format(n.createdAt.toLocal())}',
                  ),
                  trailing: fresh
                      ? Semantics(
                          label: 'Non lue',
                          child: Icon(Icons.circle, size: 10, color: c.success),
                        )
                      : null,
                  onTap: () => _open(n),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
