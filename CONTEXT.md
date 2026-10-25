# Radio Flow : contexte projet

Application multiplateforme (Android, iOS, macOS, Windows) qui structure la chaîne de production d'une station radio (RTC-MALI). Elle ne fait aucun traitement audio lourd (Audition, Audacity) : elle pilote la rédaction, le conducteur, la communication, les tâches et la centralisation des fichiers audio.

Auteur / concepteur : Chadrack Tambwe Londe. Cahier des charges validé en septembre 2026.

## Guide de design : UI/UX Pro Max Skill

**Le skill « UI/UX Pro Max » guide tous les choix de design** : design system, ergonomie mobile et desktop, accessibilité, intégration Flutter. Toute conception front-end doit le consulter avant d'écrire du code d'interface.

- Design system généré et conservé dans `design-system/radio-flow/MASTER.md`. Les surcharges par écran sont dans `design-system/radio-flow/pages/` (ex. `dashboard.md`). Lire le Master, puis la page concernée, avant de construire un écran.
- Réglages retenus : densité 8/10 (écrans denses de type tableau de bord), mouvement 3/10 (animations discrètes).
- Thème sombre prioritaire, adapté à un studio : fond `#0F172A`, cartes `#1B2336`, texte `#F8FAFC`, accent « en ligne / validé » `#22C55E`, destructif `#F87171` (éclairci après audit de contraste). Typographie Fira Sans (texte) et Fira Code (chiffres, durées, positions), embarquées dans l'application pour fonctionner hors ligne.
- Écart assumé avec la recommandation brute du skill : le style « Glassmorphism » (flou d'arrière-plan) n'est pas retenu, car coûteux sur Android d'entrée de gamme et illisible en environnement lumineux. On garde des surfaces opaques avec bordures fines.
- Règles à respecter : contraste texte 4,5:1 minimum, cibles tactiles 44×44, états de focus visibles, `reduced-motion` respecté, aucune icône emoji, jetons de couleur sémantiques (jamais de valeur hexadécimale en dur dans un widget), mise en page adaptative via `LayoutBuilder`.
- Audit d'accessibilité automatisé (`radio_flow/test/accessibility_test.dart`) : contraste WCAG des jetons (texte 4,5:1, contours 3:1) dans les deux thèmes, zones tactiles 48 dp, noms accessibles, texte agrandi 2x, paysage téléphone, tablette et grand écran, sur les 5 sections.
- Recherches utiles : `python3 ~/.claude/skills/ui-ux-pro-max/scripts/search.py "<requête>" --stack flutter` (ou `--domain ux|color|typography|chart`).

## Rôles

| Rôle | Valeur en base | Droits |
|---|---|---|
| Rédacteur en chef | `admin` | Valide les sujets du forum, arbitre, valide les textes, verrouille les conducteurs, gère les rôles |
| Journaliste / Reporteur | `journalist` | Propose des sujets, discute dans les fils, gère ses tâches, uploade ses audios finalisés |
| Technicien / Présentateur | `technician` | Consulte les conducteurs en direct, participe aux tâches, écoute et récupère les audios renommés |

## Workflow

1. **Forum** : conférence de rédaction numérique. Un journaliste soumet une idée (angle, format papier / interview / brève, source), le rédacteur en chef valide en temps réel.
2. **Fils de discussion** (style Teams) : un fil par sujet validé, ouvert à toute l'équipe, pour échanger et uploader l'audio finalisé.
3. **Conducteur dynamique** : génération automatique des conducteurs du jour (ex. Flash de 07h, Journal de 12h) d'après la grille de la station, avec un **Espace Son** (drive) par édition.
4. **Nommage automatique** à l'upload : `[Position]_[Nom_Original]_[Date_Du_Jour].[ext]`
   Exemple : `03_Reportage_Marche_2026-09-09.mp3` (compatible ZaraStudio).
   Implémenté côté base par `public.audio_stored_name(position, nom_original, date)`; le client applique la même règle avant l'upload.
5. **Tâches et tableau de bord** : tâches individuelles visibles de toute l'équipe (en reportage, en montage, en rédaction...). Le tableau de bord global fusionne les tâches en cours et le classement des productions par journaliste, en temps réel, avec sélecteur de période (hebdomadaire, mensuel, sur-mesure) et export PDF / Excel.

## Stack technique

- **Front-end** : Flutter (Android, iOS, macOS, Windows).
- **Back-end** : Supabase (PostgreSQL, Auth, Storage, Realtime / WebSockets).
- **Stockage audio** : bucket privé `conductor-audio`, chemin `{conductor_id}/{nom_renommé}`.
- **Hors ligne** : SQLite local (via Drift) pour rédiger sans connexion, synchronisation automatique au retour du réseau.

## Base de données

Migrations (à appliquer dans l'ordre) :

1. `supabase/migrations/20260901000000_radio_flow_schema.sql` : `users`, `conductors`, `conductor_lines`, `discussion_threads`, `messages`, `tasks`, RLS, temps réel, bucket audio.
2. `supabase/migrations/20260901000100_forum_and_locking.sql` : `forum_proposals` (Forum) et verrouillage des conducteurs.
3. `supabase/migrations/20260901000200_security_hardening.sql` : durcissement des fonctions.
5. `supabase/migrations/20260901000400_sound_files_view.sql` : vue `sound_files` (fichiers audio par édition et par position, soumise à la RLS de l'appelant).
8. `supabase/migrations/20260901000700_super_admin.sql` : statut de super administrateur (un seul compte, `chadracktambwe@gmail.com`), seul habilité à créer des membres, attribuer des rôles et désactiver des comptes. **À APPLIQUER AU PROJET** (en attente de confirmation côté Supabase), puis redéployer la fonction `manage-team` (son code vérifie déjà le super administrateur).
7. `supabase/migrations/20260901000600_team_management.sql` : colonne `users.active`, garde-fous (dernier administrateur, état actif modifiable seulement par le serveur).
6. `supabase/migrations/20260901000500_production_stats.sql` : fonction `production_stats(from, to)` du tableau de bord (sons publiés, sujets validés, tâches terminées et en cours par journaliste).
4. `supabase/migrations/20260901000300_conductor_grid.sql` : grille de la station (`broadcast_slots`) et fonctions `generate_conductors(date)`, `add_conductor_line(...)`, `swap_conductor_lines(a, b)`.

- `users.id` référence `auth.users`; le profil est créé automatiquement à l'inscription (rôle par défaut `journalist`). Seul un admin peut changer un rôle; le premier admin se promeut depuis l'éditeur SQL de Supabase : `update public.users set role = 'admin' where email = '...';`
- Un fil `discussion_threads` est créé automatiquement pour chaque ligne de conducteur.
- Forum : un journaliste ou un admin propose (titre, angle, format `article` / `interview` / `brief`, source); seul l'admin décide (`approved`, `rejected`, `changes_requested`), puis rattache le sujet à une ligne de conducteur via `conductor_line_id`.
- Un conducteur `locked` ou `aired` refuse tout nouvel audio (messages et stockage), sauf pour l'admin.
- RLS activée partout : lecture pour tout utilisateur connecté; écriture des conducteurs et lignes réservée à l'admin; messages et tâches modifiables par leur auteur ou un admin; upload audio réservé à `admin` et `journalist`.
- Temps réel activé sur `conductors`, `conductor_lines`, `messages`, `tasks`, `forum_proposals`.
- Les deux migrations ont été testées sur un PostgreSQL 16 local (auto-approbation, auto-promotion, upload sur conducteur verrouillé : tous refusés).

### Projet Supabase (plan gratuit)

- Projet `radio-flow`, région `eu-west-3`, identifiant `yjzzgduvoirjvhfjfszz`.
- URL : `https://yjzzgduvoirjvhfjfszz.supabase.co`
- Clé publique (publishable, prévue pour être embarquée dans l'application) : `sb_publishable_8o6zi54UEWrQPJ7l7YNzKA_fWU0AVNX`
- Les sept migrations sont appliquées au projet. La fonction serveur `manage-team` (`supabase/functions/manage-team/index.ts`, déployée, JWT obligatoire) crée et désactive les comptes pour le rédacteur en chef; la clé de service reste côté serveur.
- Conseillers de sécurité : il reste 2 avertissements voulus (`app_role()` et `conductor_is_locked()` sont appelables par les utilisateurs connectés, car les règles RLS en dépendent; elles ne renvoient que le rôle de l'appelant et un booléen de verrouillage).
- Limites du plan gratuit : environ 1 Go de stockage, 50 Mo par fichier, mise en pause après une semaine d'inactivité.

### Points restant à trancher

- **Compte administrateur** : `chadracktambwe@gmail.com` (rôle `admin`), créé avec un mot de passe provisoire communiqué dans la conversation : à changer depuis « Mon compte ». Les autres membres se créent dans l'application (Mon compte > Gérer l'équipe > Ajouter un membre) : le mot de passe provisoire est affiché une seule fois pour être transmis au membre. Un compte désactivé ne peut plus se connecter (la session déjà ouverte peut rester valable jusqu'à une heure).
- Compte de test `test.equipe@example.com` créé et désactivé pendant les essais de la fonction serveur : à supprimer (Authentication > Users).
- **Mode hors ligne** : voir `docs/ARCHITECTURE.md` (file d'envoi SQLite, périmètre et limites).
- Le **rôle technicien** n'a pas le droit d'uploader de l'audio (lecture seule des fichiers).

## Identité visuelle

- Logo fourni par le concepteur : emblème en forme d'onde sonore dans un cercle (dégradé jaune, bleu, vert) et mot-symbole « RADIO FLOW » (RADIO en blanc, FLOW en italique dégradé orange vers bleu), sur fond gris très sombre. Original : `docs/branding/radio-flow-logo.jpg`.
- Ressources dérivées (script `tools/make_brand_assets.py`) : emblème détouré (`logo_emblem.png`, seul fichier embarqué dans l'application), icône carrée iOS, avant-plan et arrière-plan de l'icône adaptative Android (emblème à 62 % du canevas, dans la zone sûre), icône Windows à coins arrondis, icône macOS au gabarit Apple.
- Dans l'interface : l'emblème est posé sur une tuile sombre (comme l'icône) pour rester lisible dans les deux thèmes; le mot-symbole est dessiné en texte, avec des teintes de dégradé ajustées au thème pour garder un bon contraste. Le logo complet figure sur l'écran de connexion, l'emblème en tête du rail latéral sur bureau.
- Nom affiché de l'application : « Radio Flow » (Android, iOS, macOS, fenêtre et propriétés Windows).
- Le vert d'accent de l'interface (`#22C55E`) est proche du vert du logo; le jaune et le bleu ne sont utilisés que dans le logo.

## Dépôt et intégration continue

- Dépôt GitHub (privé) : `chadracklonde/radioflow`, branche `main`.
- Le workflow CI (`.github/workflows/ci.yml`) vérifie l'application Flutter (analyse + tests), les migrations et la sécurité de la base sur PostgreSQL 16, les types de la fonction serveur et l'absence de secrets. Premier passage : 4 jobs verts.
- Les compilations par plateforme (`build.yml`, lancement manuel) n'ont pas encore été exécutées.

## Structure du dépôt

```
CONTEXT.md                  ce fichier
design-system/radio-flow/   design system du skill UI/UX Pro Max
supabase/migrations/        schéma SQL
radio_flow/                 application Flutter (voir docs/ARCHITECTURE.md)
```
