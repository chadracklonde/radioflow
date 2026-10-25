import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/responsive/breakpoints.dart';
import '../widgets/sync_banner.dart';
import 'destinations.dart';

/// Coque de navigation adaptative : barre basse sur téléphone, rail latéral sur bureau.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _select(int index) => navigationShell.goBranch(
    index,
    initialLocation: index == navigationShell.currentIndex,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = appDestinations[navigationShell.currentIndex];
    final account = IconButton(
      tooltip: 'Mon compte',
      icon: const Icon(Icons.account_circle_outlined),
      onPressed: () => context.push('/account'),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= Breakpoints.desktop;
        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: navigationShell.currentIndex,
                  onDestinationSelected: _select,
                  extended: constraints.maxWidth >= 1200,
                  labelType: constraints.maxWidth >= 1200
                      ? null
                      : NavigationRailLabelType.all,
                  trailing: Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: account,
                      ),
                    ),
                  ),
                  destinations: [
                    for (final d in appDestinations)
                      NavigationRailDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selectedIcon),
                        label: Text(d.label),
                      ),
                  ],
                ),
                const VerticalDivider(),
                Expanded(
                  child: Column(
                    children: [
                      const SyncBanner(),
                      Expanded(child: navigationShell),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(title: Text(current.label), actions: [account]),
          body: Column(
            children: [
              const SyncBanner(),
              Expanded(child: navigationShell),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: _select,
            destinations: [
              for (final d in appDestinations)
                NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: d.label,
                ),
            ],
          ),
        );
      },
    );
  }
}
