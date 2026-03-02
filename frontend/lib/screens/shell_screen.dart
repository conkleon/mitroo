import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class ShellScreen extends StatelessWidget {
  final Widget child;
  const ShellScreen({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final showAdmin = auth.canAccessAdminPanel;

    final paths = ['/services', '/items', '/vehicles', if (showAdmin) '/admin', '/chat'];

    final location = GoRouterState.of(context).matchedLocation;
    int idx = paths.indexWhere((p) => location.startsWith(p));
    if (idx == -1) idx = 0;

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(13),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: NavigationBar(
            selectedIndex: idx,
            onDestinationSelected: (i) => context.go(paths[i]),
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.miscellaneous_services_outlined),
                selectedIcon: Icon(Icons.miscellaneous_services),
                label: 'Services',
              ),
              const NavigationDestination(
                icon: Icon(Icons.inventory_2_outlined),
                selectedIcon: Icon(Icons.inventory_2),
                label: 'Items',
              ),
              const NavigationDestination(
                icon: Icon(Icons.directions_car_outlined),
                selectedIcon: Icon(Icons.directions_car),
                label: 'Vehicles',
              ),
              if (showAdmin)
                const NavigationDestination(
                  icon: Icon(Icons.admin_panel_settings_outlined),
                  selectedIcon: Icon(Icons.admin_panel_settings),
                  label: 'Admin',
                ),
              const NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline),
                selectedIcon: Icon(Icons.chat_bubble),
                label: 'Chat',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
