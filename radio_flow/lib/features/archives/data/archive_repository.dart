import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../conductor/domain/conductor_models.dart';
import '../../sound_space/domain/sound_file.dart';

abstract class ArchiveRepository {
  /// Conducteurs passés (avant [before], la date du jour exclue), du plus récent au plus ancien.
  Future<List<Conductor>> fetchPast({
    required DateTime before,
    int limit = 300,
  });

  /// Sons des éditions déjà diffusées, antérieurs à [before] : candidats à la suppression.
  Future<List<SoundFile>> fetchAiredSounds({required DateTime before});
}

class SupabaseArchiveRepository implements ArchiveRepository {
  SupabaseArchiveRepository(this._client);
  final SupabaseClient _client;

  String _day(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  @override
  Future<List<Conductor>> fetchPast({
    required DateTime before,
    int limit = 300,
  }) async {
    final rows = await _client
        .from('conductors')
        .select()
        .lt('broadcast_date', _day(before))
        .order('broadcast_date', ascending: false)
        .order('broadcast_time', ascending: true)
        .limit(limit);
    return rows.map(Conductor.fromJson).toList();
  }

  @override
  Future<List<SoundFile>> fetchAiredSounds({required DateTime before}) async {
    final rows = await _client
        .from('sound_files')
        .select()
        .eq('conductor_status', 'aired')
        .lt('broadcast_date', _day(before));
    return rows.map(SoundFile.fromJson).toList();
  }
}

final archiveRepositoryProvider = Provider<ArchiveRepository>(
  (ref) => SupabaseArchiveRepository(Supabase.instance.client),
);

final pastConductorsProvider = FutureProvider.autoDispose<List<Conductor>>((
  ref,
) {
  final n = DateTime.now();
  return ref
      .watch(archiveRepositoryProvider)
      .fetchPast(before: DateTime(n.year, n.month, n.day));
});
