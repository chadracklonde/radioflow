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
    this.broadcastDate,
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

  /// Date de diffusion de l'édition (sert au nom automatique du fichier).
  final DateTime? broadcastDate;

  /// Nom renommé automatiquement (dernier segment du chemin).
  String get storedName => storagePath.split('/').last;

  Map<String, dynamic> toJson() => {
    'message_id': messageId,
    'conductor_id': conductorId,
    'conductor_title': conductorTitle,
    'broadcast_time': broadcastTime == null ? null : '$broadcastTime:00',
    'line_id': lineId,
    'position_index': position,
    'line_title': lineTitle,
    'storage_path': storagePath,
    'uploaded_by': uploadedBy,
    'uploaded_at': uploadedAt.toUtc().toIso8601String(),
    'original_name': originalName,
    'audio_duration': duration,
    'conductor_status': conductorLocked ? 'locked' : 'open',
    'broadcast_date': broadcastDate == null
        ? null
        : '${broadcastDate!.year.toString().padLeft(4, '0')}-${broadcastDate!.month.toString().padLeft(2, '0')}-${broadcastDate!.day.toString().padLeft(2, '0')}',
  };

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
    broadcastDate: DateTime.tryParse((j['broadcast_date'] as String?) ?? ''),
    conductorLocked: const ['locked', 'aired'].contains(j['conductor_status']),
  );
}
