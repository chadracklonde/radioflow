import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/forum_post.dart';

abstract class ForumChatRepository {
  /// Messages en temps réel, plus récents d'abord.
  Stream<List<ForumPost>> watch();

  Future<void> send({required String authorId, required String content});

  /// RLS : l'auteur du message ou le rédacteur en chef.
  Future<void> delete(String id);
}

class SupabaseForumChatRepository implements ForumChatRepository {
  SupabaseForumChatRepository(this._client);
  final SupabaseClient _client;

  @override
  Stream<List<ForumPost>> watch() => _client
      .from('forum_posts')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .limit(200)
      .map((rows) => rows.map(ForumPost.fromJson).toList());

  @override
  Future<void> send({
    required String authorId,
    required String content,
  }) async {
    await _client.from('forum_posts').insert({
      'author_id': authorId,
      'content': content.trim(),
    });
  }

  @override
  Future<void> delete(String id) async {
    await _client.from('forum_posts').delete().eq('id', id);
  }
}

final forumChatRepositoryProvider = Provider<ForumChatRepository>(
  (ref) => SupabaseForumChatRepository(Supabase.instance.client),
);

final forumPostsProvider = StreamProvider<List<ForumPost>>(
  (ref) => ref.watch(forumChatRepositoryProvider).watch(),
);
