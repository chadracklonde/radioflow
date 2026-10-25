import 'dart:async';

import '../local/local_store.dart';
import 'connectivity_service.dart';
import 'sync_engine.dart';

class SyncStatus {
  const SyncStatus({
    required this.online,
    required this.pending,
    required this.failed,
    required this.syncing,
  });
  final bool online;
  final int pending;
  final int failed;
  final bool syncing;

  bool get idle => online && pending == 0 && failed == 0;

  @override
  bool operator ==(Object other) =>
      other is SyncStatus &&
      other.online == online &&
      other.pending == pending &&
      other.failed == failed &&
      other.syncing == syncing;

  @override
  int get hashCode => Object.hash(online, pending, failed, syncing);
}

/// Surveille le réseau et la file d'attente, et envoie dès que possible.
class SyncService {
  SyncService({
    required this.store,
    required this.connectivity,
    required Map<String, OpHandler> handlers,
    this.retryEvery = const Duration(seconds: 30),
  }) : _engine = SyncEngine(store, handlers);

  final LocalStore store;
  final ConnectivityService connectivity;
  final SyncEngine _engine;
  final Duration retryEvery;

  final _status = StreamController<SyncStatus>.broadcast();
  final _reconnect = StreamController<void>.broadcast();
  StreamSubscription<bool>? _connSub;
  StreamSubscription<List<OutboxItem>>? _storeSub;
  Timer? _timer;
  bool _started = false;
  bool _disposed = false;
  bool _online = true;
  bool _syncing = false;
  int _pending = 0;
  int _failed = 0;

  SyncStatus get current => SyncStatus(
    online: _online,
    pending: _pending,
    failed: _failed,
    syncing: _syncing,
  );

  Stream<SyncStatus> get status {
    late final StreamController<SyncStatus> out;
    StreamSubscription<SyncStatus>? sub;
    out = StreamController<SyncStatus>(
      onListen: () {
        out.add(current);
        sub = _status.stream.listen(out.add);
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  /// Émet quand le réseau revient : les flux en lecture se reconnectent.
  Stream<void> get reconnect => _reconnect.stream;

  void _emit() {
    if (!_disposed) _status.add(current);
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _online = await connectivity.isOnline();
    _connSub = connectivity.changes.listen((online) {
      final regained = online && !_online;
      _online = online;
      if (regained) {
        _reconnect.add(null);
        flush();
      }
      _emit();
    });
    _storeSub = store.watch().listen((items) {
      _pending = items.where((i) => !i.failed).length;
      _failed = items.where((i) => i.failed).length;
      if (_pending > 0) {
        _timer ??= Timer.periodic(retryEvery, (_) => flush());
        if (_online) flush();
      } else {
        _timer?.cancel();
        _timer = null;
      }
      _emit();
    });
    _emit();
  }

  Future<void> flush() async {
    if (_syncing || _disposed) return;
    _syncing = true;
    _emit();
    try {
      final result = await _engine.flush();
      if (result.stoppedOffline) {
        _online = false;
      } else if (result.sent > 0 && !_online) {
        _online = true;
        _reconnect.add(null);
      }
    } finally {
      _syncing = false;
      _emit();
    }
  }

  Future<void> retryFailed() async {
    await store.retryFailed();
    await flush();
  }

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    await _connSub?.cancel();
    await _storeSub?.cancel();
    await _status.close();
    await _reconnect.close();
  }
}
