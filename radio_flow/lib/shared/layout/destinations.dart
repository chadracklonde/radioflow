import 'package:flutter/material.dart';

/// Les cinq sections principales (maximum conseillé pour une barre de navigation basse).
class AppDestination {
  const AppDestination(
    this.path,
    this.label,
    this.icon,
    this.selectedIcon,
    this.description,
  );

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String description;
}

const appDestinations = <AppDestination>[
  AppDestination(
    '/forum',
    'Forum',
    Icons.forum_outlined,
    Icons.forum,
    'Propositions de sujets et décisions du rédacteur en chef.',
  ),
  AppDestination(
    '/conductor',
    'Conducteur',
    Icons.view_list_outlined,
    Icons.view_list,
    'Conducteurs du jour et fils de discussion par ligne.',
  ),
  AppDestination(
    '/sound',
    'Espace Son',
    Icons.library_music_outlined,
    Icons.library_music,
    'Fichiers audio classés et renommés automatiquement.',
  ),
  AppDestination(
    '/tasks',
    'Tâches',
    Icons.checklist_outlined,
    Icons.checklist,
    'Tâches en cours de toute l’équipe.',
  ),
  AppDestination(
    '/dashboard',
    'Tableau de bord',
    Icons.dashboard_outlined,
    Icons.dashboard,
    'Vue d’ensemble des tâches et des productions par journaliste.',
  ),
];
