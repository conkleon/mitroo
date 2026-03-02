import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../screens/login_screen.dart';
import '../screens/admin_panel_screen.dart';
import '../screens/create_service_screen.dart';
import '../screens/manage_users_screen.dart';
import '../screens/manage_departments_screen.dart';
import '../screens/manage_specializations_screen.dart';
import '../screens/services_screen.dart';
import '../screens/items_screen.dart';
import '../screens/vehicles_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/shell_screen.dart';

GoRouter appRouter(AuthProvider auth) {
  return GoRouter(
    initialLocation: '/services',
    refreshListenable: auth,
    redirect: (context, state) {
      final loggedIn = auth.isAuthenticated;
      final loggingIn = state.matchedLocation == '/login';

      if (!loggedIn && !loggingIn) return '/login';
      if (loggedIn && loggingIn) return '/services';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      // Profile is a full-screen route outside the shell
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      // Admin sub-screens (full-screen, outside shell)
      GoRoute(
        path: '/admin/services/create',
        builder: (context, state) {
          final deptId = int.tryParse(state.uri.queryParameters['departmentId'] ?? '');
          final deptName = state.uri.queryParameters['departmentName'];
          return CreateServiceScreen(
            initialDepartmentId: deptId,
            initialDepartmentName: deptName,
          );
        },
      ),
      GoRoute(
        path: '/admin/users',
        builder: (context, state) => const ManageUsersScreen(),
      ),
      GoRoute(
        path: '/admin/departments',
        builder: (context, state) => const ManageDepartmentsScreen(),
      ),
      GoRoute(
        path: '/admin/specializations',
        builder: (context, state) => const ManageSpecializationsScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => ShellScreen(child: child),
        routes: [
          GoRoute(
            path: '/services',
            builder: (context, state) => const ServicesScreen(),
          ),
          GoRoute(
            path: '/items',
            builder: (context, state) => const ItemsScreen(),
          ),
          GoRoute(
            path: '/vehicles',
            builder: (context, state) => const VehiclesScreen(),
          ),
          GoRoute(
            path: '/admin',
            builder: (context, state) => const AdminPanelScreen(),
          ),
          GoRoute(
            path: '/chat',
            builder: (context, state) => const ChatScreen(),
          ),
        ],
      ),
    ],
  );
}
