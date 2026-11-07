import 'package:flutter/material.dart';

import '../shared/widgets/empty_state.dart';

enum AppDestination {
  home('Home', Icons.home_outlined),
  discover('Discover', Icons.search),
  community('Community', Icons.forum_outlined),
  messages('Messages', Icons.chat_bubble_outline),
  account('Account', Icons.person_outline);

  const AppDestination(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Workspaces are reachable only through AuthGate.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.account,
    this.discovery,
    this.community,
    this.messaging,
    this.notificationAction,
    this.callAction,
    this.settingsAction,
    this.initialDestination = AppDestination.home,
  });
  final AppDestination initialDestination;
  final Widget? account;
  final Widget? discovery;
  final Widget? community;
  final Widget? messaging;
  final Widget? notificationAction;
  final Widget? callAction;
  final Widget? settingsAction;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _selectedIndex = widget.initialDestination.index;
  late bool _discoveryVisited =
      widget.initialDestination == AppDestination.discover;
  late bool _communityVisited =
      widget.initialDestination == AppDestination.community;
  late bool _messagesVisited =
      widget.initialDestination == AppDestination.messages;
  void _select(int index) => setState(() {
    _selectedIndex = index;
    if (index == AppDestination.discover.index) _discoveryVisited = true;
    if (index == AppDestination.community.index) _communityVisited = true;
    if (index == AppDestination.messages.index) _messagesVisited = true;
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 720;
      final extended = constraints.maxWidth >= 1100;
      final destination = AppDestination.values[_selectedIndex];
      return Scaffold(
        appBar: AppBar(
          title: const Text('Attorlink'),
          actions: [
            if (widget.settingsAction != null) widget.settingsAction!,
            if (widget.callAction != null) widget.callAction!,
            if (widget.notificationAction != null) widget.notificationAction!,
          ],
        ),
        body: SafeArea(
          child: Row(
            children: [
              if (wide) ...[
                NavigationRail(
                  extended: extended,
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _select,
                  labelType: extended
                      ? NavigationRailLabelType.none
                      : NavigationRailLabelType.all,
                  destinations: [
                    for (final item in AppDestination.values)
                      NavigationRailDestination(
                        icon: Icon(item.icon),
                        label: Text(item.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
              ],
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_discoveryVisited && widget.discovery != null)
                          Offstage(
                            key: const ValueKey('discovery-tab'),
                            offstage: destination != AppDestination.discover,
                            child: ExcludeFocus(
                              excluding: destination != AppDestination.discover,
                              child: TickerMode(
                                enabled: destination == AppDestination.discover,
                                child: widget.discovery!,
                              ),
                            ),
                          ),
                        if (_communityVisited && widget.community != null)
                          Offstage(
                            key: const ValueKey('community-tab'),
                            offstage: destination != AppDestination.community,
                            child: ExcludeFocus(
                              excluding:
                                  destination != AppDestination.community,
                              child: TickerMode(
                                enabled:
                                    destination == AppDestination.community,
                                child: widget.community!,
                              ),
                            ),
                          ),
                        if (_messagesVisited && widget.messaging != null)
                          Offstage(
                            key: const ValueKey('messages-tab'),
                            offstage: destination != AppDestination.messages,
                            child: ExcludeFocus(
                              excluding: destination != AppDestination.messages,
                              child: TickerMode(
                                enabled: destination == AppDestination.messages,
                                child: widget.messaging!,
                              ),
                            ),
                          ),
                        if ((destination != AppDestination.discover ||
                                widget.discovery == null) &&
                            (destination != AppDestination.community ||
                                widget.community == null) &&
                            (destination != AppDestination.messages ||
                                widget.messaging == null))
                          if (destination == AppDestination.account &&
                              widget.account != null)
                            widget.account!
                          else if (destination == AppDestination.home)
                            ListView(
                              padding: const EdgeInsets.all(24),
                              children: [
                                Text(
                                  'Welcome to Attorlink',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall,
                                ),
                                const SizedBox(height: 16),
                                for (final entry in [
                                  if (widget.discovery != null)
                                    (AppDestination.discover, 'Find a lawyer'),
                                  if (widget.community != null)
                                    (
                                      AppDestination.community,
                                      'Community feed',
                                    ),
                                  if (widget.messaging != null)
                                    (AppDestination.messages, 'Conversations'),
                                  if (widget.account != null)
                                    (AppDestination.account, 'Your profile'),
                                ])
                                  ListTile(
                                    leading: Icon(entry.$1.icon),
                                    title: Text(entry.$2),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => _select(entry.$1.index),
                                  ),
                              ],
                            )
                          else
                            EmptyState(
                              key: ValueKey(destination),
                              icon: destination.icon,
                              title: destination.label,
                              message: 'This section is unavailable.',
                            ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: _selectedIndex,
                onDestinationSelected: _select,
                destinations: [
                  for (final item in AppDestination.values)
                    NavigationDestination(
                      icon: Icon(item.icon),
                      label: item.label,
                    ),
                ],
              ),
      );
    },
  );
}
