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
  });

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
  });

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
  );
}

class BroadcastSlot {
  const BroadcastSlot({
    required this.id,
    required this.title,
    required this.time,
    required this.active,
  });
  final String id;
  final String title;
  final String time; // HH:mm
  final bool active;

  factory BroadcastSlot.fromJson(Map<String, dynamic> j) => BroadcastSlot(
    id: j['id'] as String,
    title: j['title'] as String,
    time: (j['broadcast_time'] as String).substring(0, 5),
    active: j['active'] as bool,
  );
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
