import 'package:flutter/material.dart';

import 'responsive_layout.dart';

class AdaptiveDestination {
  const AdaptiveDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
    this.title,
    this.actions,
  });

  final List<AdaptiveDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;
  final Widget? title;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final appBar = AppBar(title: title, actions: actions);

    return ResponsiveLayout(
      compact: (_) => Scaffold(
        appBar: appBar,
        body: body,
        bottomNavigationBar: destinations.length < 2
            ? null
            : NavigationBar(
                selectedIndex: selectedIndex,
                onDestinationSelected: onDestinationSelected,
                destinations: [
                  for (final d in destinations)
                    NavigationDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: d.label,
                    ),
                ],
              ),
      ),
      medium: (_) => _withRail(context, appBar, extended: false),
      expanded: (_) => _withRail(context, appBar, extended: true),
    );
  }

  Widget _withRail(
    BuildContext context,
    AppBar appBar, {
    required bool extended,
  }) {
    return Scaffold(
      appBar: appBar,
      body: Row(
        children: [
          if (destinations.length >= 2) ...[
            NavigationRail(
              extended: extended,
              minExtendedWidth: 220,
              labelType: extended
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              destinations: [
                for (final d in destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
          ],
          // Ограничиваем ширину контента на ультрашироких мониторах
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: body,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
