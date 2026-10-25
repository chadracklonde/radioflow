class ThreadMessage {
  const ThreadMessage({
    required this.id,
    required this.userId,
    required this.createdAt,
    this.content,
    this.audioUrl,
    this.audioName,
    this.audioDuration,
    this.pendingSync = false,
  });

  final String id;
  final String userId;
  final DateTime createdAt;
  final String? content;
  final String? audioUrl;
  final String? audioName;
  final int? audioDuration;

  /// Écrit hors ligne, pas encore envoyé au serveur.
  final bool pendingSync;

  bool get hasAudio => audioUrl != null;

  factory ThreadMessage.fromJson(Map<String, dynamic> j) => ThreadMessage(
    id: j['id'] as String,
    userId: j['user_id'] as String,
    createdAt: DateTime.parse(j['created_at'] as String),
    content: j['content'] as String?,
    audioUrl: j['audio_file_url'] as String?,
    audioName: j['audio_original_name'] as String?,
    audioDuration: j['audio_duration'] as int?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'created_at': createdAt.toUtc().toIso8601String(),
    'content': content,
    'audio_file_url': audioUrl,
    'audio_original_name': audioName,
    'audio_duration': audioDuration,
  };
}
