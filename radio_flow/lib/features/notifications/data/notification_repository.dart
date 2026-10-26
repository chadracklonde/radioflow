import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/data/auth_repository.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.createdAt,
    this.body,
    this.refType,
    this.refId,
    this.readAt,
  });

  final String id;

  /// `proposal.new`, `proposal.approved`, `proposal.rejected`, `sound.new`.
  final String kind;
  final String title;
  final String? body;
  final String? refType;
  final String? refId;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get unread => readAt == null;

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
    id: j['id'] as String,
    kind: j['kind'] as String,
    title: j['title'] as String,
    body: j['body'] as String?,
    refType: j['ref_type'] as String?,
    refId: j['ref_id'] as String?,
    createdAt: DateTime.parse(j['created_at'] as String),
    readAt: DateTime.tryParse((j['read_at'] as String?) ?? ''),
  );
}

abstract class NotificationRepository {
  /// Notifications de l'utilisateur, les plus récentes d'abord, en temps réel.
  Stream<List<AppNotification>> watch();
  Future<void> markAllRead();
}

class SupabaseNotificationRepository implements NotificationRepository {
  SupabaseNotificationRepository(this._client);
  final SupabaseClient _client;

  @override
  Stream<List<AppNotification>> watch() {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const Stream.empty();
    return _client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(100)
        .map((rows) => rows.map(AppNotification.fromJson).toList());
  }

  @override
  Future<void> markAllRead() async {
    await _client.rpc('mark_notifications_read');
  }
}

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => SupabaseNotificationRepository(Supabase.instance.client),
);

/// Notifications de la session en cours (vide si personne n'est connecté).
final notificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final signedIn = ref.watch(signedInProvider).value ?? false;
  if (!signedIn) return Stream.value(const []);
  return ref.watch(notificationRepositoryProvider).watch();
});

final unreadCountProvider = Provider<int>(
  (ref) =>
      ref.watch(notificationsProvider).value?.where((n) => n.unread).length ??
      0,
);
