import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/account/presentation/account_screen.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/conductor/data/conductor_repository.dart';
import '../../features/conductor/presentation/conductor_detail_screen.dart';
import '../../features/conductor/presentation/conductor_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/forum/presentation/forum_screen.dart';
import '../../features/tasks/presentation/tasks_screen.dart';
import '../../features/team/presentation/team_screen.dart';
import '../../features/sound_space/presentation/sound_space_screen.dart';
import '../../features/threads/presentation/thread_screen.dart';
import '../../shared/layout/app_shell.dart';
import '../../shared/layout/destinations.dart';
import '../../shared/widgets/section_placeholder.dart';

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final signedIn = ValueNotifier<bool>(
    ref.read(signedInProvider).value ?? false,
  );
  ref.listen(
    signedInProvider,
    (_, next) => signedIn.value = next.value ?? false,
  );
  ref.onDispose(signedIn.dispose);

  final router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: appDestinations.first.path,
    refreshListenable: signedIn,
    redirect: (context, state) {
      final atLogin = state.matchedLocation == '/login';
      if (!signedIn.value) return atLogin ? null : '/login';
      if (atLogin) return appDestinations.first.path;
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      // Écrans plein écran, au-dessus de la coque de navigation.
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/forum/:proposalId/thread',
        builder: (_, state) =>
            ThreadScreen(proposalId: state.pathParameters['proposalId']!),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/team',
        builder: (_, _) => const TeamScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/account',
        builder: (_, _) => const AccountScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/conductor/:id',
        builder: (_, state) => ConductorDetailScreen(
          conductorId: state.pathParameters['id']!,
          date: isoDate(ref.read(selectedDateProvider)),
        ),
        routes: [
          GoRoute(
            parentNavigatorKey: _rootKey,
            path: 'line/:lineId',
            builder: (_, state) => ThreadScreen(
              conductorId: state.pathParameters['id']!,
              lineId: state.pathParameters['lineId']!,
            ),
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(navigationShell: shell),
        branches: [
          for (final d in appDestinations)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: d.path,
                  builder: (_, _) => switch (d.path) {
                    '/forum' => const ForumScreen(),
                    '/conductor' => const ConductorScreen(),
                    '/sound' => const SoundSpaceScreen(),
                    '/tasks' => const TasksScreen(),
                    '/dashboard' => const DashboardScreen(),
                    _ => SectionPlaceholder(
                      icon: d.selectedIcon,
                      title: d.label,
                      description:
                          '${d.description}\nCette section est en cours de développement.',
                    ),
                  },
                ),
              ],
            ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
