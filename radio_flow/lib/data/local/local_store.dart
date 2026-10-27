import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opération d'écriture en attente d'envoi (rédigée hors ligne).
class OutboxItem {
  const OutboxItem({
    required this.id,
    required this.kind,
    required this.payload,
    required this.createdAt,
    required this.attempts,
    this.error,
  });

  final int id;
  final String kind;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int attempts;

  /// Renseigné quand le serveur a refusé l'opération (elle ne sera plus retentée seule).
  final String? error;

  bool get failed => error != null;
}

/// Stockage local : file d'attente d'écritures + dernière version des listes consultées.
///
/// - [SqlLocalStore] (téléphone, ordinateur) : base SQLite sur le disque, conservée entre deux lancements.
/// - [MemoryLocalStore] (web, tests) : en mémoire, perdue à la fermeture de l'onglet.
abstract class LocalStore {
  Future<OutboxItem> enqueue(String kind, Map<String, dynamic> payload);
  Future<List<OutboxItem>> items();

  /// Émet la file actuelle, puis à chaque changement.
  Stream<List<OutboxItem>> watch();
  Future<bool> hasPending();
  Future<void> remove(int id);
  Future<void> recordAttempt(int id);
  Future<void> markFailed(int id, String error);

  /// Remet les opérations refusées dans la file.
  Future<void> retryFailed();
  Future<void> discardFailed();
  Future<List<dynamic>?> readCache(String key);
  Future<void> writeCache(String key, List<Map<String, dynamic>> rows);

  /// À la déconnexion : les données consultées ne doivent pas rester pour le prochain utilisateur.
  /// La file d'attente est conservée pour ne perdre aucune rédaction.
  Future<void> clearCache();
  void dispose();
}

/// Stockage en mémoire : utilisé sur le web (pas de base locale persistante) et dans les tests.
class MemoryLocalStore implements LocalStore {
  final _items = <OutboxItem>[];
  final _cache = <String, List<dynamic>>{};
  final _changes = StreamController<void>.broadcast();
  int _nextId = 1;

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  void _replace(int id, OutboxItem Function(OutboxItem) change) {
    final i = _items.indexWhere((x) => x.id == id);
    if (i >= 0) _items[i] = change(_items[i]);
  }

  @override
  Future<OutboxItem> enqueue(String kind, Map<String, dynamic> payload) async {
    // copie JSON : comme sur disque, la file ne garde pas de référence vivante
    final item = OutboxItem(
      id: _nextId++,
      kind: kind,
      payload: jsonDecode(jsonEncode(payload)) as Map<String, dynamic>,
      createdAt: DateTime.now().toUtc(),
      attempts: 0,
    );
    _items.add(item);
    _notify();
    return item;
  }

  @override
  Future<List<OutboxItem>> items() async => List.of(_items);

  @override
  Stream<List<OutboxItem>> watch() {
    late final StreamController<List<OutboxItem>> out;
    StreamSubscription<void>? sub;
    out = StreamController<List<OutboxItem>>(
      onListen: () {
        out.add(List.of(_items));
        sub = _changes.stream.listen((_) => out.add(List.of(_items)));
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  @override
  Future<bool> hasPending() async => _items.any((i) => !i.failed);

  @override
  Future<void> remove(int id) async {
    _items.removeWhere((i) => i.id == id);
    _notify();
  }

  @override
  Future<void> recordAttempt(int id) async => _replace(
    id,
    (i) => OutboxItem(
      id: i.id,
      kind: i.kind,
      payload: i.payload,
      createdAt: i.createdAt,
      attempts: i.attempts + 1,
      error: i.error,
    ),
  );

  @override
  Future<void> markFailed(int id, String error) async {
    _replace(
      id,
      (i) => OutboxItem(
        id: i.id,
        kind: i.kind,
        payload: i.payload,
        createdAt: i.createdAt,
        attempts: i.attempts + 1,
        error: error,
      ),
    );
    _notify();
  }

  @override
  Future<void> retryFailed() async {
    for (final i in List.of(_items)) {
      if (i.failed) {
        _replace(
          i.id,
          (x) => OutboxItem(
            id: x.id,
            kind: x.kind,
            payload: x.payload,
            createdAt: x.createdAt,
            attempts: x.attempts,
          ),
        );
      }
    }
    _notify();
  }

  @override
  Future<void> discardFailed() async {
    _items.removeWhere((i) => i.failed);
    _notify();
  }

  @override
  Future<List<dynamic>?> readCache(String key) async {
    final v = _cache[key];
    return v == null ? null : jsonDecode(jsonEncode(v)) as List<dynamic>;
  }

  @override
  Future<void> writeCache(String key, List<Map<String, dynamic>> rows) async {
    _cache[key] = jsonDecode(jsonEncode(rows)) as List<dynamic>;
  }

  @override
  Future<void> clearCache() async => _cache.clear();

  @override
  void dispose() => _changes.close();
}

/// Remplacé dans `main()` par la base du disque (téléphone, ordinateur); en mémoire par défaut
/// (web, tests).
final localStoreProvider = Provider<LocalStore>((ref) {
  final store = MemoryLocalStore();
  ref.onDispose(store.dispose);
  return store;
});
