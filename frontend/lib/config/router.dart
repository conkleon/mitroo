import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../screens/login_screen.dart';
import '../screens/admin_panel_screen.dart';
import '../screens/create_service_screen.dart';
import '../screens/manage_services_screen.dart';
import '../screens/past_services_screen.dart';
import '../screens/service_detail_screen.dart';
import '../screens/manage_users_screen.dart';
import '../screens/user_detail_screen.dart';
import '../screens/manage_departments_screen.dart';
import '../screens/department_detail_screen.dart';
import '../screens/manage_specializations_screen.dart';
import '../screens/specialization_detail_screen.dart';
import '../screens/services_screen.dart';
import '../screens/items_screen.dart';
import '../screens/item_detail_screen.dart';
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
      ShellRoute(
        builder: (context, state, child) => ShellScreen(child: child),
        routes: [
          GoRoute(
            path: '/services',
            builder: (context, state) => const ServicesScreen(),
          ),
          GoRoute(
            path: '/services/:id',
            builder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
              return ServiceDetailScreen(serviceId: id);
            },
          ),
          GoRoute(
            path: '/items',
            builder: (context, state) => const ItemsScreen(),
          ),
          GoRoute(
            path: '/items/:id',
            builder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
              return ItemDetailScreen(itemId: id);
            },
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
            path: '/admin/services',
            builder: (context, state) {
              final deptId = int.tryParse(state.uri.queryParameters['departmentId'] ?? '');
              final deptName = state.uri.queryParameters['departmentName'] ?? 'Department';
              return ManageServicesScreen(
                key: ValueKey('manage-services-${deptId ?? 0}'),
                departmentId: deptId ?? 0,
                departmentName: deptName,
              );
            },
          ),
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
            path: '/admin/services/past',
            builder: (context, state) {
              final deptId = int.tryParse(state.uri.queryParameters['departmentId'] ?? '');
              final deptName = state.uri.queryParameters['departmentName'] ?? 'Department';
              return PastServicesScreen(
                key: ValueKey('past-services-${deptId ?? 0}'),
                departmentId: deptId ?? 0,
                departmentName: deptName,
              );
            },
          ),
          GoRoute(
            path: '/admin/services/:id',
            builder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
              return ServiceDetailScreen(serviceId: id);
            },
          ),
          GoRoute(
            path: '/admin/services/:id/edit',
            builder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
              final deptId = int.tryParse(state.uri.queryParameters['departmentId'] ?? '');
              final deptName = state.uri.queryParameters['departmentName'];
              return CreateServiceScreen(
                editServiceId: id,
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
            path: '/admin/users/:id',
            builder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
              return UserDetailScreen(userId: id);
            },
          ),
          GoRoute(
            path: '/admin/departments',
            builder: (context, state) => const ManageDepartmentsScreen(),
          ),
          GoRoute(
            path: '/admin/departments/:id',
            builder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
              return DepartmentDetailScreen(departmentId: id);
            },
          ),
          GoRoute(
            path: '/admin/specializations',
            builder: (context, state) => const ManageSpecializationsScreen(),
          ),
          GoRoute(
            path: '/admin/specializations/:id',
            builder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
              return SpecializationDetailScreen(specializationId: id);
            },
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
