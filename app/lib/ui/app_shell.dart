import 'package:fade_call/core/theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

typedef ShellDestination = ({IconData icon, IconData selected, String label});

/// Bottom navigation on phones, a navigation rail on wide screens.
class AppShell extends StatelessWidget {
  const AppShell({
    required this.shell,
    required this.destinations,
    super.key,
    this.railBreakpoint = 840,
  });

  final StatefulNavigationShell shell;
  final List<ShellDestination> destinations;
  final double railBreakpoint;

  void _go(int index) =>
      shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < railBreakpoint) {
      return Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: _go,
          destinations: [
            for (final d in destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selected),
                label: d.label,
              ),
          ],
        ),
      );
    }
    final extended = width >= 1200;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: extended,
            minExtendedWidth: 220,
            selectedIndex: shell.currentIndex,
            onDestinationSelected: _go,
            labelType: extended
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: Gap.lg),
              child: _RailBrand(extended: extended),
            ),
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selected),
                  label: Text(d.label),
                ),
            ],
          ),
          Expanded(child: shell),
        ],
      ),
    );
  }
}

class _RailBrand extends StatelessWidget {
  const _RailBrand({required this.extended});

  final bool extended;

  @override
  Widget build(BuildContext context) {
    final mark = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Palette.brass, width: 2),
      ),
      child: SizedBox.square(
        dimension: 40,
        child: Center(
          child: Text(
            'F',
            style: context.text.titleLarge?.copyWith(color: Palette.cream),
          ),
        ),
      ),
    );
    if (!extended) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: Gap.sm + 4),
        Text(
          'Fade Call',
          style: context.text.titleLarge?.copyWith(color: Palette.cream),
        ),
      ],
    );
  }
}
