import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'local_store.dart';
import 'sql_local_store.dart';

/// Base SQLite sur le disque (téléphone, ordinateur).
Future<LocalStore> openLocalStore() async {
  final dir = await getApplicationSupportDirectory();
  return SqlLocalStore(sqlite3.open(p.join(dir.path, 'radio_flow.db')));
}
