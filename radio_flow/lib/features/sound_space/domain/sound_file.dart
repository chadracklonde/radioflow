class SoundFile {
  const SoundFile({
    required this.messageId,
    required this.conductorId,
    required this.conductorTitle,
    required this.broadcastTime,
    required this.lineId,
    required this.position,
    required this.lineTitle,
    required this.storagePath,
    required this.uploadedBy,
    required this.uploadedAt,
    this.originalName,
    this.duration,
    this.conductorLocked = false,
  });

  final String messageId;
  final String conductorId;
  final String conductorTitle;
  final String? broadcastTime;
  final String lineId;
  final int position;
  final String lineTitle;

  /// Chemin dans le bucket : `{conductor_id}/{nom_renommé}`.
  final String storagePath;
  final String uploadedBy;
  final DateTime uploadedAt;
  final String? originalName;
  final int? duration;

  /// Édition verrouillée ou diffusée : seul le rédacteur en chef modifie les sons.
  final bool conductorLocked;

  /// Nom renommé automatiquement (dernier segment du chemin).
  String get storedName => storagePath.split('/').last;

  factory SoundFile.fromJson(Map<String, dynamic> j) => SoundFile(
    messageId: j['message_id'] as String,
    conductorId: j['conductor_id'] as String,
    conductorTitle: j['conductor_title'] as String,
    broadcastTime: (j['broadcast_time'] as String?)?.substring(0, 5),
    lineId: j['line_id'] as String,
    position: j['position_index'] as int,
    lineTitle: j['line_title'] as String,
    storagePath: j['storage_path'] as String,
    uploadedBy: j['uploaded_by'] as String,
    uploadedAt: DateTime.parse(j['uploaded_at'] as String),
    originalName: j['original_name'] as String?,
    duration: j['audio_duration'] as int?,
    conductorLocked: const ['locked', 'aired'].contains(j['conductor_status']),
  );
}
