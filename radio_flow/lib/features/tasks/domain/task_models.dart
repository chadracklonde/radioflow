import 'package:flutter/material.dart';

enum TaskStatus {
  todo('À faire', Icons.radio_button_unchecked),
  reporting('En reportage', Icons.mic),
  writing('En rédaction', Icons.edit_outlined),
  editing('En montage', Icons.content_cut),
  review('En relecture', Icons.visibility_outlined),
  done('Terminée', Icons.check_circle_outline);

  const TaskStatus(this.label, this.icon);
  final String label;
  final IconData icon;

  static TaskStatus parse(String v) => TaskStatus.values.firstWhere(
    (s) => s.name == v,
    orElse: () => TaskStatus.todo,
  );
}

class TeamTask {
  const TeamTask({
    required this.id,
    required this.userId,
    required this.title,
    required this.status,
    this.dueDate,
    this.pendingSync = false,
  });

  final String id;
  final String userId;
  final String title;
  final TaskStatus status;
  final DateTime? dueDate;

  /// Créée ou modifiée hors ligne, pas encore envoyée au serveur.
  final bool pendingSync;

  bool get isDone => status == TaskStatus.done;

  bool isOverdue(DateTime today) =>
      !isDone &&
      dueDate != null &&
      dueDate!.isBefore(DateTime(today.year, today.month, today.day));

  factory TeamTask.fromJson(Map<String, dynamic> j) => TeamTask(
    id: j['id'] as String,
    userId: j['user_id'] as String,
    title: j['title'] as String,
    status: TaskStatus.parse(j['status'] as String),
    dueDate: j['due_date'] == null
        ? null
        : DateTime.parse(j['due_date'] as String),
  );

  TeamTask copyWith({TaskStatus? status, bool? pendingSync}) => TeamTask(
    id: id,
    userId: userId,
    title: title,
    status: status ?? this.status,
    dueDate: dueDate,
    pendingSync: pendingSync ?? this.pendingSync,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'title': title,
    'status': status.name,
    'due_date': dueDate?.toIso8601String().substring(0, 10),
  };
}
