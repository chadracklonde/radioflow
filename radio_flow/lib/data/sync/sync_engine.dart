import '../../core/network/network_errors.dart';
import '../local/local_store.dart';

typedef OpHandler = Future<void> Function(Map<String, dynamic> payload);

class FlushResult {
  const FlushResult({
    required this.sent,
    required this.failed,
    required this.stoppedOffline,
  });
  final int sent;
  final int failed;

  /// Vrai si l'envoi s'est arrêté faute de réseau (à retenter plus tard).
  final bool stoppedOffline;
}

/// Envoie la file d'attente dans l'ordre de rédaction.
class SyncEngine {
  SyncEngine(this._store, this._handlers);

  final LocalStore _store;
  final Map<String, OpHandler> _handlers;
  bool _running = false;

  Future<FlushResult> flush() async {
    if (_running) {
      return const FlushResult(sent: 0, failed: 0, stoppedOffline: false);
    }
    _running = true;
    var sent = 0, failed = 0;
    var offline = false;
    try {
      for (final item in await _store.items()) {
        if (item.failed) continue;
        final handler = _handlers[item.kind];
        if (handler == null) continue; // type inconnu : conservé, jamais perdu
        try {
          await handler(item.payload);
          await _store.remove(item.id);
          sent++;
        } catch (e) {
          if (isDuplicate(e)) {
            // Déjà enregistré lors d'un envoi précédent dont la réponse s'est perdue.
            await _store.remove(item.id);
            sent++;
          } else if (isNetworkError(e)) {
            await _store.recordAttempt(item.id);
            offline = true;
            break; // on garde l'ordre : rien ne passe devant une opération en attente
          } else {
            await _store.markFailed(item.id, _describe(e));
            failed++;
          }
        }
      }
    } finally {
      _running = false;
    }
    return FlushResult(sent: sent, failed: failed, stoppedOffline: offline);
  }

  String _describe(Object e) {
    final s = e.toString();
    return s.length > 200 ? s.substring(0, 200) : s;
  }
}
