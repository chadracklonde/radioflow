/// Message du Forum, l'espace de discussion libre de l'équipe.
/// Les propositions de sujets, elles, sont dans la section « Rédaction ».
class ForumPost {
  const ForumPost({
    required this.id,
    required this.content,
    required this.createdAt,
    this.authorId,
    this.isSystem = false,
  });

  final String id;

  /// Null pour un message système (le rappel quotidien, signé « Radio Flow »).
  final String? authorId;
  final bool isSystem;
  final String content;
  final DateTime createdAt;

  factory ForumPost.fromJson(Map<String, dynamic> json) => ForumPost(
    id: json['id'] as String,
    authorId: json['author_id'] as String?,
    isSystem: (json['is_system'] as bool?) ?? false,
    content: json['content'] as String,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
  );
}
