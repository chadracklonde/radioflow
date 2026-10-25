import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/network/supabase_config.dart';
import 'data/local/local_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr');
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  // Base locale : file d'envoi hors ligne et dernières données consultées.
  final dir = await getApplicationSupportDirectory();
  final db = sqlite3.open(p.join(dir.path, 'radio_flow.db'));

  runApp(
    ProviderScope(
      overrides: [
        localStoreProvider.overrideWith((ref) {
          final store = LocalStore(db);
          ref.onDispose(store.dispose);
          return store;
        }),
      ],
      child: const RadioFlowApp(),
    ),
  );
}
