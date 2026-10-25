import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class ConnectivityService {
  Future<bool> isOnline();

  /// Émet true / false quand l'état du réseau change.
  Stream<bool> get changes;
}

/// Indique si une interface réseau est active (pas si le serveur répond : l'envoi tranche).
class ConnectivityPlusService implements ConnectivityService {
  final _connectivity = Connectivity();

  static bool _online(List<ConnectivityResult> r) =>
      r.any((x) => x != ConnectivityResult.none);

  @override
  Future<bool> isOnline() async {
    try {
      return _online(await _connectivity.checkConnectivity());
    } catch (_) {
      return true; // plateforme sans détection : on tente et l'envoi tranche
    }
  }

  @override
  Stream<bool> get changes =>
      _connectivity.onConnectivityChanged.map(_online).handleError((_) {});
}

final connectivityServiceProvider = Provider<ConnectivityService>(
  (ref) => ConnectivityPlusService(),
);
