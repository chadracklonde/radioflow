import 'local_store.dart';

/// Web : pas de base locale persistante. Les modifications en attente restent en mémoire
/// tant que l'onglet est ouvert.
Future<LocalStore> openLocalStore() async => MemoryLocalStore();
