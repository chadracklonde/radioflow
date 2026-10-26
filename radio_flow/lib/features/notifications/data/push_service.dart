import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/data/profile_repository.dart';
import '../../../core/router/app_router.dart';

/// Notifications push de l'appareil (Firebase Cloud Messaging), isolées pour les tests.
///
/// Sans configuration Firebase (fichier `google-services.json` absent), l'enregistrement
/// échoue sans bruit : les notifications restent disponibles dans la cloche de l'application.
abstract class PushService {
  /// Autorise les notifications et enregistre l'appareil pour [userId].
  /// Renvoie false si ce n'est pas possible (Firebase non configuré, autorisation refusée…).
  Future<bool> register(String userId);

  /// Retire cet appareil du compte (à la déconnexion).
  Future<void> unregister();

  /// Données de la notification sur laquelle l'utilisateur a touché.
  Stream<Map<String, String>> get opened;
}

class NoPushService implements PushService {
  const NoPushService();
  @override
  Future<bool> register(String userId) async => false;
  @override
  Future<void> unregister() async {}
  @override
  Stream<Map<String, String>> get opened => const Stream.empty();
}

class FirebasePushService implements PushService {
  FirebasePushService(this._client);
  final SupabaseClient _client;

  String? _token;
  StreamSubscription<String>? _refreshSub;

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  String get _platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  Future<void> _save(String token) => _client.rpc(
    'register_device_token',
    params: {'p_token': token, 'p_platform': _platform},
  );

  @override
  Future<bool> register(String userId) async {
    if (!supported) return false;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return false;
      }
      // L'API getToken est marquée « dépréciée » au profit des identifiants d'installation (FID),
      // mais l'envoi côté serveur (FCM v1) repose sur le jeton classique : on le garde.
      // ignore: deprecated_member_use
      final token = await messaging.getToken();
      if (token == null) return false;
      _token = token;
      await _save(token);
      // ignore: deprecated_member_use
      _refreshSub ??= messaging.onTokenRefresh.listen((t) {
        _token = t;
        _save(t).catchError((Object _) {});
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> unregister() async {
    final token = _token;
    _token = null;
    await _refreshSub?.cancel();
    _refreshSub = null;
    if (token == null) return;
    try {
      await _client.from('device_tokens').delete().eq('token', token);
      // ignore: deprecated_member_use
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  @override
  Stream<Map<String, String>> get opened {
    if (!supported) return const Stream.empty();
    late final StreamController<Map<String, String>> out;
    StreamSubscription<RemoteMessage>? sub;
    out = StreamController<Map<String, String>>(
      onListen: () async {
        try {
          if (Firebase.apps.isEmpty) await Firebase.initializeApp();
          final initial = await FirebaseMessaging.instance.getInitialMessage();
          if (initial != null) out.add(_data(initial));
          sub = FirebaseMessaging.onMessageOpenedApp.listen(
            (m) => out.add(_data(m)),
          );
        } catch (_) {}
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  Map<String, String> _data(RemoteMessage m) => {
    for (final e in m.data.entries) e.key: '${e.value}',
  };
}

final pushServiceProvider = Provider<PushService>(
  (ref) => FirebasePushService.supported
      ? FirebasePushService(Supabase.instance.client)
      : const NoPushService(),
);

/// Écran à ouvrir pour une notification touchée.
String? routeForNotification(Map<String, String> data) =>
    switch (data['ref_type']) {
      'proposal' => '/forum',
      'message' => '/sound',
      _ => null,
    };

/// Enregistre l'appareil dès qu'un utilisateur est connecté et ouvre l'écran concerné
/// quand on touche une notification. À observer une fois, depuis la racine de l'application.
final pushBootstrapProvider = Provider<void>((ref) {
  String? registeredFor;
  ref.listen(profileProvider, (_, next) async {
    final profile = next.value;
    if (profile == null || registeredFor == profile.id) return;
    registeredFor = profile.id;
    try {
      await ref.read(pushServiceProvider).register(profile.id);
    } catch (_) {}
  }, fireImmediately: true);

  StreamSubscription<Map<String, String>>? sub;
  try {
    sub = ref.read(pushServiceProvider).opened.listen((data) {
      final route = routeForNotification(data);
      if (route != null) ref.read(routerProvider).go(route);
    });
  } catch (_) {}
  ref.onDispose(() => sub?.cancel());
});
