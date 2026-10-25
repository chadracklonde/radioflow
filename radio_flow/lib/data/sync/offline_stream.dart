import 'dart:async';

import '../local/local_store.dart';

/// Liste « hors ligne d'abord » : affiche la dernière version connue, la met à jour depuis le
/// serveur en temps réel, et superpose les opérations en attente d'envoi.
///
/// - Sans réseau et sans copie locale : l'erreur est transmise (l'écran propose de réessayer).
/// - Avec une copie locale : l'erreur réseau est ignorée, la copie reste affichée, et la
///   connexion est retentée au retour du réseau (ou toutes les 15 s).
Stream<List<T>> offlineFirst<T>({
  required LocalStore store,
  required String key,
  required Stream<List<T>> Function() remote,
  required Map<String, dynamic> Function(T) toJson,
  required T Function(Map<String, dynamic>) fromJson,
  required List<T> Function(List<T> base, List<OutboxItem> outbox) overlay,
  required Stream<void> reconnect,
  Duration retryAfter = const Duration(seconds: 15),
}) {
  late final StreamController<List<T>> out;
  var base = <T>[];
  var outbox = <OutboxItem>[];
  var hasData = false;
  StreamSubscription<List<T>>? remoteSub;
  StreamSubscription<List<OutboxItem>>? outboxSub;
  StreamSubscription<void>? reconnectSub;
  Timer? timer;

  void emit() {
    if (!out.isClosed) out.add(overlay(List.of(base), outbox));
  }

  void connect() {
    timer?.cancel();
    remoteSub?.cancel();
    remoteSub = remote().listen(
      (list) {
        base = list;
        hasData = true;
        store.writeCache(key, [for (final x in list) toJson(x)]);
        emit();
      },
      onError: (Object e, StackTrace s) {
        if (!hasData && !out.isClosed) out.addError(e, s);
        timer = Timer(retryAfter, connect);
      },
      cancelOnError: true,
    );
  }

  out = StreamController<List<T>>(
    onListen: () async {
      final cached = await store.readCache(key);
      if (cached != null) {
        base = [
          for (final r in cached) fromJson(Map<String, dynamic>.from(r as Map)),
        ];
        hasData = true;
      }
      outboxSub = store.watch().listen((o) {
        outbox = o;
        if (hasData || o.isNotEmpty) emit();
      });
      reconnectSub = reconnect.listen((_) => connect());
      connect();
    },
    onCancel: () async {
      timer?.cancel();
      await remoteSub?.cancel();
      await outboxSub?.cancel();
      await reconnectSub?.cancel();
    },
  );
  return out.stream;
}
