import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/sqlite3.dart';

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

/// Stockage local SQLite : file d'attente d'écritures + dernière version des listes consultées.
class LocalStore {
  LocalStore(this._db) {
    _db.execute('''
      create table if not exists outbox (
        id integer primary key autoincrement,
        kind text not null,
        payload text not null,
        created_at text not null,
        attempts integer not null default 0,
        error text
      );
      create table if not exists cache (
        key text primary key,
        json text not null,
        updated_at text not null
      );
    ''');
  }

  final Database _db;
  final _changes = StreamController<void>.broadcast();

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  List<OutboxItem> _readItems() {
    final rows = _db.select(
      'select id, kind, payload, created_at, attempts, error from outbox order by id',
    );
    return [
      for (final r in rows)
        OutboxItem(
          id: r['id'] as int,
          kind: r['kind'] as String,
          payload: jsonDecode(r['payload'] as String) as Map<String, dynamic>,
          createdAt: DateTime.parse(r['created_at'] as String),
          attempts: r['attempts'] as int,
          error: r['error'] as String?,
        ),
    ];
  }

  Future<OutboxItem> enqueue(String kind, Map<String, dynamic> payload) async {
    _db.execute(
      'insert into outbox (kind, payload, created_at) values (?, ?, ?)',
      [kind, jsonEncode(payload), DateTime.now().toUtc().toIso8601String()],
    );
    final id = _db.lastInsertRowId;
    _notify();
    return _readItems().firstWhere((i) => i.id == id);
  }

  Future<List<OutboxItem>> items() async => _readItems();

  /// Émet la file actuelle, puis à chaque changement.
  /// (Pas de `async*` : l'annulation d'un tel flux attendrait le prochain changement.)
  Stream<List<OutboxItem>> watch() {
    late final StreamController<List<OutboxItem>> out;
    StreamSubscription<void>? sub;
    out = StreamController<List<OutboxItem>>(
      onListen: () {
        out.add(_readItems());
        sub = _changes.stream.listen((_) => out.add(_readItems()));
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  Future<bool> hasPending() async =>
      (_db
              .select('select count(*) c from outbox where error is null')
              .first['c']
          as int) >
      0;

  Future<void> remove(int id) async {
    _db.execute('delete from outbox where id = ?', [id]);
    _notify();
  }

  Future<void> recordAttempt(int id) async {
    _db.execute('update outbox set attempts = attempts + 1 where id = ?', [id]);
  }

  Future<void> markFailed(int id, String error) async {
    _db.execute(
      'update outbox set error = ?, attempts = attempts + 1 where id = ?',
      [error, id],
    );
    _notify();
  }

  /// Remet les opérations refusées dans la file.
  Future<void> retryFailed() async {
    _db.execute('update outbox set error = null where error is not null');
    _notify();
  }

  Future<void> discardFailed() async {
    _db.execute('delete from outbox where error is not null');
    _notify();
  }

  Future<List<dynamic>?> readCache(String key) async {
    final rows = _db.select('select json from cache where key = ?', [key]);
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first['json'] as String) as List<dynamic>;
  }

  Future<void> writeCache(String key, List<Map<String, dynamic>> rows) async {
    _db.execute(
      'insert into cache (key, json, updated_at) values (?, ?, ?) '
      'on conflict(key) do update set json = excluded.json, updated_at = excluded.updated_at',
      [key, jsonEncode(rows), DateTime.now().toUtc().toIso8601String()],
    );
  }

  /// À la déconnexion : les données consultées ne doivent pas rester pour le prochain utilisateur.
  /// La file d'attente est conservée pour ne perdre aucune rédaction.
  Future<void> clearCache() async => _db.execute('delete from cache');

  void dispose() {
    _changes.close();
    _db.close();
  }
}

/// Remplacé dans `main()` par la base du disque; en mémoire par défaut (tests).
final localStoreProvider = Provider<LocalStore>((ref) {
  final store = LocalStore(sqlite3.openInMemory());
  ref.onDispose(store.dispose);
  return store;
});
