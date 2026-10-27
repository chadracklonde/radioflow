import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/network/supabase_config.dart';
import 'data/local/local_store.dart';
import 'data/local/open_store_io.dart'
    if (dart.library.js_interop) 'data/local/open_store_web.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr');
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  // Base locale : file d'envoi hors ligne et dernières données consultées.
  final store = await openLocalStore();

  runApp(
    ProviderScope(
      overrides: [
        localStoreProvider.overrideWith((ref) {
          ref.onDispose(store.dispose);
          return store;
        }),
      ],
      child: const RadioFlowApp(),
    ),
  );
}
