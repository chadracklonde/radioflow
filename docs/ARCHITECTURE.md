# Architecture Flutter : Radio Flow

## Initialisation

Flutter n'est pas installé dans cet environnement; à lancer sur votre machine, depuis la racine du dépôt :

```bash
flutter create --org ml.rtcmali --project-name radio_flow --platforms=android,ios,macos,windows radio_flow
```

La commande complète le dossier `radio_flow/` existant (les dossiers `lib/` déjà créés sont conservés). Les cibles iOS et macOS ne se compilent que sous macOS, Windows que sous Windows.

Dépendances proposées :

```bash
cd radio_flow
flutter pub add flutter_riverpod go_router supabase_flutter \
  drift sqlite3_flutter_libs path_provider path \
  file_picker just_audio connectivity_plus \
  pdf printing excel intl
flutter pub add --dev drift_dev build_runner flutter_lints
```

Les polices Fira Sans et Fira Code sont à placer dans `assets/fonts/` et déclarées dans `pubspec.yaml` (pas de téléchargement à l'exécution, pour le mode hors ligne).

## État d'avancement

Fait et testé (`flutter analyze` sans erreur, 114 tests réussis) : thème sombre et clair avec jetons sémantiques, navigation adaptative (barre basse sous 900 px, rail latéral au-delà), écran de connexion Supabase, routage protégé par la session, Forum complet (liste en temps réel, filtres par statut, formulaire de proposition, décision du rédacteur en chef avec note; 8 tests de widgets). Conducteur et fils de discussion (voir ci-dessous). Espace Son (voir ci-dessous). Tâches et Tableau de bord (voir ci-dessous). Les cinq sections sont fonctionnelles, plus l'écran « Équipe » (réservé au super administrateur : liste des membres, changement de rôle, ajout d'un membre avec mot de passe provisoire affiché une fois et copiable, désactivation / réactivation avec confirmation) et l'écran « Mon compte » (profil et rôle, changement de mot de passe avec vérification de l'ancien, déconnexion toujours disponible même si le profil ne se charge pas, avertissement si des modifications n'ont pas été envoyées).

Tâches : tâches de toute l'équipe en temps réel, filtres En cours / Terminées / Mes tâches, création avec échéance facultative, statuts (à faire, en reportage, en rédaction, en montage, en relecture, terminée), retard signalé; chacun gère les siennes, l'admin gère toutes. Tableau de bord : période (semaine, mois, sur mesure), indicateurs, classement des journalistes (une production = un son publié dans un fil; les sujets validés et tâches terminées complètent le bilan), tâches en cours de l'équipe, export PDF et Excel (classement + tâches en cours).

Espace Son : envoi d'un audio depuis un fil (bouton pièce jointe; formats mp3, wav, m4a, aac, ogg, flac, wma; 50 Mo maximum), nommage automatique `[Position]_[Nom_Original]_[Date].[ext]` avec la date de diffusion de l'édition, stockage dans `conductor-audio/{conductor_id}/`, liste de la journée groupée par édition, lecture intégrée (lien signé d'une heure) et téléchargement. Pas encore fait : détection de la durée des fichiers, suppression d'un fichier, lecture sur appareil réel.

Conducteur : navigation par date, génération des éditions d'après la grille (admin), lignes avec réordonnancement et statuts, verrouillage, fil de discussion par ligne en temps réel (texte; l'envoi d'audio arrive avec l'Espace Son). 114 tests au total.

À noter : le nommage des fichiers audio utilise la position de la ligne; réordonner des lignes après upload ne renomme pas les fichiers existants.

Mode hors ligne : base SQLite locale (`radio_flow.db`) avec une file d'envoi et une copie des dernières listes consultées. Sans réseau, les journalistes peuvent proposer un sujet, créer / modifier / supprimer des tâches et écrire dans les fils; ces actions sont envoyées dans l'ordre au retour du réseau (identifiants générés côté appareil : un renvoi ne crée pas de doublon), signalées par un bandeau et la mention « En attente d'envoi ». Un refus du serveur (droits...) n'est jamais perdu en silence : il apparaît dans le bandeau avec « Réessayer » / « Supprimer ». Restent en ligne uniquement : décisions du Forum, édition du Conducteur et de la grille, envoi de fichiers audio. La déconnexion efface la copie des listes mais conserve la file d'envoi.

Non fait : polices Fira (le téléchargement des fichiers est bloqué depuis ce conteneur; à placer dans `assets/fonts/` puis déclarer `FiraSans` et `FiraCode` dans `pubspec.yaml`), compilation Android / iOS / macOS / Windows.

## Arborescence `lib/` (par fonctionnalité)

```
lib/
├── main.dart
├── app.dart                 MaterialApp.router, thèmes clair et sombre
├── core/
│   ├── theme/               jetons de couleur, typographie, espacements, ThemeData (source : design-system/radio-flow/MASTER.md)
│   ├── responsive/          points de rupture, adaptation mobile (barre du bas) / desktop (rail latéral)
│   ├── router/              go_router, garde d'authentification et de rôle
│   ├── network/             client Supabase, état de connexion
│   ├── offline/             file d'attente des écritures hors ligne
│   └── utils/               nommage audio, formats de durée et de date
├── data/
│   ├── local/               base SQLite (Drift)
│   ├── remote/              accès Supabase (tables, storage, realtime)
│   └── sync/                synchronisation locale <-> distante
├── shared/
│   ├── widgets/             composants du design system (boutons, cartes, pastilles de statut, lecteur audio)
│   └── layout/              coque de navigation adaptative
└── features/
    ├── auth/
    ├── forum/
    ├── threads/             fils de discussion
    ├── conductor/
    ├── sound_space/         Espace Son, nommage et upload
    ├── tasks/
    └── dashboard/           tableau de bord global, export PDF / Excel
```

Chaque dossier de `features/` suit le même découpage interne : `data/` (dépôts), `domain/` (modèles), `presentation/` (écrans, widgets, contrôleurs Riverpod).

## Règles de design appliquées (UI/UX Pro Max, stack Flutter)

- Thème via `Theme.of(context)` uniquement; aucune couleur ni `TextStyle` en dur dans les widgets.
- Thème sombre par défaut, `darkTheme` et `theme` tous deux fournis.
- Mise en page adaptative avec `LayoutBuilder` : barre de navigation du bas (5 entrées maximum) sur mobile, rail latéral sur macOS et Windows.
- Densité élevée sur le tableau de bord et le conducteur; cibles tactiles d'au moins 44×44 sur mobile.
- Retour visuel sur chaque action (chargement, succès, erreur près du champ), états de focus visibles pour l'usage clavier sur desktop.
- Animations de 150 à 300 ms, désactivées si l'utilisateur demande une réduction des animations.
- Un statut n'est jamais communiqué par la seule couleur : toujours une icône ou un libellé en plus.
