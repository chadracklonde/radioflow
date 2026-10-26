import 'package:flutter/material.dart';

enum ProposalFormat {
  article('Papier', Icons.article_outlined),
  interview('Interview', Icons.mic_none),
  brief('Brève', Icons.bolt_outlined);

  const ProposalFormat(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum ProposalStatus {
  pending('En attente', Icons.hourglass_empty),
  approved('Validé', Icons.check_circle_outline),
  rejected('Refusé', Icons.cancel_outlined),
  changesRequested('À revoir', Icons.edit_note);

  const ProposalStatus(this.label, this.icon);
  final String label;
  final IconData icon;

  /// Valeur de l'énumération PostgreSQL `proposal_status`.
  String get dbValue => switch (this) {
    ProposalStatus.changesRequested => 'changes_requested',
    _ => name,
  };

  static ProposalStatus fromDb(String v) => ProposalStatus.values.firstWhere(
    (s) => s.dbValue == v,
    orElse: () => ProposalStatus.pending,
  );
}

class ForumProposal {
  const ForumProposal({
    required this.id,
    required this.authorId,
    required this.title,
    required this.angle,
    required this.format,
    required this.status,
    required this.createdAt,
    this.source,
    this.decisionNote,
    this.conductorLineId,
    this.pendingSync = false,
  });

  final String id;
  final String authorId;
  final String title;
  final String angle;
  final ProposalFormat format;
  final ProposalStatus status;
  final DateTime createdAt;
  final String? source;
  final String? decisionNote;

  /// Ligne du conducteur où le sujet a été placé (null tant qu'il n'est pas placé).
  final String? conductorLineId;

  /// Rédigée hors ligne, pas encore envoyée au serveur.
  final bool pendingSync;

  factory ForumProposal.fromJson(Map<String, dynamic> j) => ForumProposal(
    id: j['id'] as String,
    authorId: j['author_id'] as String,
    title: j['title'] as String,
    angle: j['angle'] as String,
    format: ProposalFormat.values.firstWhere(
      (f) => f.name == j['format'],
      orElse: () => ProposalFormat.article,
    ),
    status: ProposalStatus.fromDb(j['status'] as String),
    createdAt: DateTime.parse(j['created_at'] as String),
    source: j['source'] as String?,
    decisionNote: j['decision_note'] as String?,
    conductorLineId: j['conductor_line_id'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'author_id': authorId,
    'title': title,
    'angle': angle,
    'format': format.name,
    'status': status.dbValue,
    'created_at': createdAt.toUtc().toIso8601String(),
    'source': source,
    'decision_note': decisionNote,
    'conductor_line_id': conductorLineId,
  };
}
