import 'package:flutter/material.dart';

enum ConductorStatus {
  draft('Brouillon', Icons.edit_outlined),
  open('Ouvert', Icons.lock_open),
  locked('Verrouillé', Icons.lock_outline),
  aired('Diffusé', Icons.cell_tower);

  const ConductorStatus(this.label, this.icon);
  final String label;
  final IconData icon;

  static ConductorStatus parse(String v) => ConductorStatus.values.firstWhere(
    (s) => s.name == v,
    orElse: () => ConductorStatus.draft,
  );

  bool get isLocked => this == locked || this == aired;
}

enum LineItemType {
  jingle('Jingle', Icons.music_note),
  intro('Introduction', Icons.play_circle_outline),
  reportage('Reportage', Icons.mic),
  interview('Interview', Icons.record_voice_over_outlined),
  brief('Brève', Icons.bolt_outlined),
  chronicle('Chronique', Icons.menu_book_outlined),
  weather('Météo', Icons.wb_sunny_outlined),
  ad('Publicité', Icons.campaign_outlined),
  outro('Conclusion', Icons.stop_circle_outlined),
  other('Autre', Icons.more_horiz);

  const LineItemType(this.label, this.icon);
  final String label;
  final IconData icon;

  static LineItemType parse(String v) => LineItemType.values.firstWhere(
    (t) => t.name == v,
    orElse: () => LineItemType.other,
  );
}

enum LineStatus {
  planned('Prévu', Icons.radio_button_unchecked),
  inProgress('En cours', Icons.autorenew),
  ready('Prêt', Icons.check_circle_outline),
  aired('Diffusé', Icons.cell_tower),
  dropped('Abandonné', Icons.remove_circle_outline);

  const LineStatus(this.label, this.icon);
  final String label;
  final IconData icon;

  String get dbValue => switch (this) {
    LineStatus.inProgress => 'in_progress',
    _ => name,
  };

  static LineStatus parse(String v) => LineStatus.values.firstWhere(
    (s) => s.dbValue == v,
    orElse: () => LineStatus.planned,
  );
}

class Conductor {
  const Conductor({
    required this.id,
    required this.title,
    required this.broadcastDate,
    required this.status,
    this.broadcastTime,
    this.targetDuration,
    this.slotId,
  });

  /// Durée cible de l'émission en secondes (reprise du créneau de la grille).
  final int? targetDuration;

  /// Créneau de la grille dont le conducteur est issu (modèle de lignes).
  final String? slotId;

  final String id;
  final String title;
  final DateTime broadcastDate;
  final ConductorStatus status;

  /// Heure de diffusion « HH:mm », si connue.
  final String? broadcastTime;

  factory Conductor.fromJson(Map<String, dynamic> j) => Conductor(
    id: j['id'] as String,
    title: j['title'] as String,
    broadcastDate: DateTime.parse(j['broadcast_date'] as String),
    status: ConductorStatus.parse(j['status'] as String),
    broadcastTime: (j['broadcast_time'] as String?)?.substring(0, 5),
    targetDuration: j['target_duration'] as int?,
    slotId: j['slot_id'] as String?,
  );
}

class ConductorLine {
  const ConductorLine({
    required this.id,
    required this.conductorId,
    required this.position,
    required this.itemType,
    required this.title,
    required this.status,
    this.plannedDuration,
    this.script,
  });

  /// Texte à lire à l'antenne.
  final String? script;

  final String id;
  final String conductorId;
  final int position;
  final LineItemType itemType;
  final String title;
  final LineStatus status;

  /// Durée prévue en secondes.
  final int? plannedDuration;

  factory ConductorLine.fromJson(Map<String, dynamic> j) => ConductorLine(
    id: j['id'] as String,
    conductorId: j['conductor_id'] as String,
    position: j['position_index'] as int,
    itemType: LineItemType.parse(j['item_type'] as String),
    title: j['title'] as String,
    status: LineStatus.parse(j['status'] as String),
    plannedDuration: j['planned_duration'] as int?,
    script: j['script'] as String?,
  );
}

class BroadcastSlot {
  const BroadcastSlot({
    required this.id,
    required this.title,
    required this.time,
    required this.active,
    this.weekdays = allWeekdays,
    this.durationSeconds,
  });

  /// Durée de l'émission en secondes, si connue.
  final int? durationSeconds;

  final String id;
  final String title;
  final String time; // HH:mm
  final bool active;

  /// Jours de diffusion, 1 = lundi … 7 = dimanche (comme `DateTime.weekday`).
  final List<int> weekdays;

  static const allWeekdays = [1, 2, 3, 4, 5, 6, 7];

  bool airsOn(DateTime date) => active && weekdays.contains(date.weekday);

  factory BroadcastSlot.fromJson(Map<String, dynamic> j) => BroadcastSlot(
    id: j['id'] as String,
    title: j['title'] as String,
    time: (j['broadcast_time'] as String).substring(0, 5),
    active: j['active'] as bool,
    weekdays: [
      for (final d in (j['weekdays'] as List?) ?? allWeekdays)
        (d as num).toInt(),
    ],
    durationSeconds: j['duration_seconds'] as int?,
  );
}

/// Une ligne de l'historique des modifications d'un conducteur.
class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.summary,
    required this.createdAt,
    this.userId,
  });
  final int id;
  final String summary;
  final DateTime createdAt;
  final String? userId;

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
    id: j['id'] as int,
    summary: j['summary'] as String,
    createdAt: DateTime.parse(j['created_at'] as String),
    userId: j['user_id'] as String?,
  );
}

/// Chronométrage d'un conducteur : durée prévue par ligne, remplacée par la durée
/// réelle du son quand il a été envoyé. Les lignes abandonnées ne comptent pas.
class ConductorTiming {
  const ConductorTiming({
    required this.planned,
    required this.estimated,
    required this.withSound,
    required this.counted,
  });

  final int planned;
  final int estimated;
  final int withSound;
  final int counted;

  /// [soundSeconds] : durée du son (le plus récent) par identifiant de ligne.
  factory ConductorTiming.compute(
    List<ConductorLine> lines,
    Map<String, int> soundSeconds,
  ) {
    var planned = 0, estimated = 0, withSound = 0, counted = 0;
    for (final l in lines) {
      if (l.status == LineStatus.dropped) continue;
      counted++;
      final p = l.plannedDuration ?? 0;
      final real = soundSeconds[l.id];
      planned += p;
      if (real != null) withSound++;
      estimated += real ?? p;
    }
    return ConductorTiming(
      planned: planned,
      estimated: estimated,
      withSound: withSound,
      counted: counted,
    );
  }
}

/// 90 -> « 1:30 ».
String formatDuration(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// « 2:30 » ou « 150 » (secondes) -> secondes; null si invalide.
int? parseDuration(String input) {
  final v = input.trim();
  if (v.isEmpty) return null;
  final parts = v.split(':');
  if (parts.length == 1) return int.tryParse(parts[0]);
  if (parts.length == 2) {
    final m = int.tryParse(parts[0]);
    final s = int.tryParse(parts[1]);
    if (m == null || s == null || s < 0 || s > 59 || m < 0) return null;
    return m * 60 + s;
  }
  return null;
}
