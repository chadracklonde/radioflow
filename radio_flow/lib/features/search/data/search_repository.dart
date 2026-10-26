import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum SearchKind {
  proposal('Sujets'),
  line('Lignes de conducteur'),
  message('Discussions'),
  sound('Sons');

  const SearchKind(this.label);
  final String label;
}

/// Un résultat de recherche, avec de quoi ouvrir l'écran concerné.
class SearchHit {
  const SearchHit({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle,
    this.date,
    this.conductorId,
    this.lineId,
    this.proposalId,
    this.proposalApproved = false,
  });

  final SearchKind kind;
  final String id;
  final String title;
  final String? subtitle;

  /// Date de diffusion de l'édition concernée, si elle existe.
  final DateTime? date;
  final String? conductorId;
  final String? lineId;
  final String? proposalId;
  final bool proposalApproved;
}

abstract class SearchRepository {
  Future<List<SearchHit>> search(String query);
}

/// Protège % et _ pour qu'ils soient cherchés tels quels.
String likePattern(String query) {
  final escaped = query
      .trim()
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
  return '%$escaped%';
}

class SupabaseSearchRepository implements SearchRepository {
  SupabaseSearchRepository(this._client);
  final SupabaseClient _client;

  static const _limit = 15;

  @override
  Future<List<SearchHit>> search(String query) async {
    final p = likePattern(query);
    final results = await Future.wait([
      _proposals(p),
      _lines(p),
      _messages(p),
      _sounds(p),
    ]);
    return [for (final r in results) ...r];
  }

  Future<List<SearchHit>> _proposals(String p) async {
    final byTitle = await _client
        .from('forum_proposals')
        .select('id, title, angle, status')
        .ilike('title', p)
        .limit(_limit);
    final byAngle = await _client
        .from('forum_proposals')
        .select('id, title, angle, status')
        .ilike('angle', p)
        .limit(_limit);
    final seen = <String>{};
    return [
      for (final r in [...byTitle, ...byAngle])
        if (seen.add(r['id'] as String))
          SearchHit(
            kind: SearchKind.proposal,
            id: r['id'] as String,
            title: r['title'] as String,
            subtitle: r['angle'] as String?,
            proposalId: r['id'] as String,
            proposalApproved: r['status'] == 'approved',
          ),
    ].take(_limit).toList();
  }

  Future<List<SearchHit>> _lines(String p) async {
    const cols =
        'id, title, script, conductor_id, conductors(title, broadcast_date)';
    final byTitle = await _client
        .from('conductor_lines')
        .select(cols)
        .ilike('title', p)
        .limit(_limit);
    final byScript = await _client
        .from('conductor_lines')
        .select(cols)
        .ilike('script', p)
        .limit(_limit);
    final seen = <String>{};
    return [
      for (final r in [...byTitle, ...byScript])
        if (seen.add(r['id'] as String)) _lineHit(r),
    ].take(_limit).toList();
  }

  SearchHit _lineHit(Map<String, dynamic> r) {
    final c = r['conductors'] as Map<String, dynamic>?;
    return SearchHit(
      kind: SearchKind.line,
      id: r['id'] as String,
      title: r['title'] as String,
      subtitle: c?['title'] as String?,
      date: DateTime.tryParse((c?['broadcast_date'] as String?) ?? ''),
      conductorId: r['conductor_id'] as String,
      lineId: r['id'] as String,
    );
  }

  Future<List<SearchHit>> _messages(String p) async {
    final rows = await _client
        .from('messages')
        .select(
          'id, content, discussion_threads(proposal_id, conductor_line_id, '
          'conductor_lines(conductor_id, title, conductors(title, broadcast_date)))',
        )
        .ilike('content', p)
        .order('created_at', ascending: false)
        .limit(_limit);
    return [
      for (final r in rows)
        () {
          final t = r['discussion_threads'] as Map<String, dynamic>?;
          final line = t?['conductor_lines'] as Map<String, dynamic>?;
          final cond = line?['conductors'] as Map<String, dynamic>?;
          return SearchHit(
            kind: SearchKind.message,
            id: r['id'] as String,
            title: r['content'] as String,
            subtitle: line?['title'] as String?,
            date: DateTime.tryParse((cond?['broadcast_date'] as String?) ?? ''),
            conductorId: line?['conductor_id'] as String?,
            lineId: t?['conductor_line_id'] as String?,
            proposalId: t?['proposal_id'] as String?,
          );
        }(),
    ];
  }

  Future<List<SearchHit>> _sounds(String p) async {
    const cols =
        'message_id, conductor_id, line_id, original_name, storage_path, '
        'broadcast_date, conductor_title, line_title';
    final byName = await _client
        .from('sound_files')
        .select(cols)
        .ilike('original_name', p)
        .limit(_limit);
    final byPath = await _client
        .from('sound_files')
        .select(cols)
        .ilike('storage_path', p)
        .limit(_limit);
    final seen = <String>{};
    return [
      for (final r in [...byName, ...byPath])
        if (seen.add(r['message_id'] as String))
          SearchHit(
            kind: SearchKind.sound,
            id: r['message_id'] as String,
            title: (r['storage_path'] as String).split('/').last,
            subtitle: '${r['conductor_title']} · ${r['line_title']}',
            date: DateTime.tryParse((r['broadcast_date'] as String?) ?? ''),
            conductorId: r['conductor_id'] as String,
            lineId: r['line_id'] as String,
          ),
    ].take(_limit).toList();
  }
}

final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => SupabaseSearchRepository(Supabase.instance.client),
);
