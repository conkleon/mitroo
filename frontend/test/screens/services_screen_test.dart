import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mitroo_frontend/screens/services_screen.dart';
import 'package:mitroo_frontend/providers/auth_provider.dart';
import 'package:mitroo_frontend/providers/service_provider.dart';

// ── Fake ServiceProvider ──────────────────────────────────────────
class _FakeServiceProvider extends ServiceProvider {
  final List<dynamic> _fakeServices;

  _FakeServiceProvider({List<dynamic> fakeServices = const []})
      : _fakeServices = fakeServices;

  @override
  List<dynamic> get services => _fakeServices;

  @override
  bool get loading => false;

  @override
  bool get isStale => false;

  @override
  Future<void> fetchMyServices() async {}
}

// ── Fake AuthProvider ─────────────────────────────────────────────
class _FakeAuthProvider extends AuthProvider {
  @override
  bool get isAuthenticated => true;

  @override
  bool get isAdmin => false;

  @override
  bool get isMissionAdmin => false;

  @override
  Map<String, dynamic>? get user => {'forename': 'Test', 'surname': 'User'};

  @override
  String get displayName => 'Test User';

  @override
  List<dynamic> get specializations => [];
}

// ── Service data factory ──────────────────────────────────────────
Map<String, dynamic> _makeService(
  int id,
  String name, {
  Map<String, dynamic>? serviceType,
}) =>
    {
      'id': id,
      'name': name,
      'carrier': '',
      'startAt': '2026-06-10T09:00:00.000Z',
      'endAt': '2026-06-10T17:00:00.000Z',
      'location': '',
      'description': '',
      'defaultHours': 0,
      'defaultHoursVol': 0,
      'defaultHoursTraining': 0,
      'defaultHoursTrainers': 0,
      'defaultHoursTEP': 0,
      'userServices': [],
      '_count': {'userServices': 0},
      'serviceType': serviceType,
    };

// ── Widget builder ────────────────────────────────────────────────
Widget _buildSubject({
  required _FakeServiceProvider serviceProvider,
  _FakeAuthProvider? authProvider,
}) {
  final auth = authProvider ?? _FakeAuthProvider();

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => MultiProvider(
          providers: [
            ChangeNotifierProvider<ServiceProvider>.value(value: serviceProvider),
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ],
          child: const ServicesScreen(),
        ),
      ),
    ],
  );

  return MaterialApp.router(routerConfig: router);
}

// ─────────────────────────────────────────────────────────────────
void main() {
  setUpAll(() async {
    await initializeDateFormatting('el_GR');
  });

  setUp(() {
    // Start in List view (tab index 0) to avoid calendar locale issues.
    SharedPreferences.setMockInitialValues({'services_view_tab_index': 0});
  });

  // Test 1: Tab bar hidden when all services share one type
  testWidgets('tab bar hidden when all services share one type', (tester) async {
    final provider = _FakeServiceProvider(
      fakeServices: [
        _makeService(1, 'Service A', serviceType: {'id': 10, 'name': 'Κάλυψη'}),
        _makeService(2, 'Service B', serviceType: {'id': 10, 'name': 'Κάλυψη'}),
      ],
    );

    await tester.pumpWidget(_buildSubject(serviceProvider: provider));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Λίστα'));
    await tester.pumpAndSettle();

    expect(find.text('Service A'), findsOneWidget); // confirms list rendered
    // The type-tab bar must NOT appear when only 1 type exists.
    expect(find.text('Κάλυψη (2)'), findsNothing);
  });

  // Test 2: Tab bar hidden when no service has a serviceType
  testWidgets('tab bar hidden when no service has a serviceType', (tester) async {
    final provider = _FakeServiceProvider(
      fakeServices: [
        _makeService(1, 'Service A', serviceType: null),
      ],
    );

    await tester.pumpWidget(_buildSubject(serviceProvider: provider));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Λίστα'));
    await tester.pumpAndSettle();

    expect(find.text('Service A'), findsOneWidget); // confirms list rendered
    // No type tab labels should be present at all.
    expect(find.textContaining('(1)'), findsNothing);
    expect(find.textContaining('(2)'), findsNothing);
  });

  // Test 3: Tab bar shown with correct counts when 2+ types exist
  testWidgets('tab bar shown with correct counts when 2+ types exist', (tester) async {
    final provider = _FakeServiceProvider(
      fakeServices: [
        _makeService(1, 'Coverage 1', serviceType: {'id': 10, 'name': 'Κάλυψη'}),
        _makeService(2, 'Coverage 2', serviceType: {'id': 10, 'name': 'Κάλυψη'}),
        _makeService(3, 'Training 1', serviceType: {'id': 20, 'name': 'Εκπαίδευση'}),
      ],
    );

    await tester.pumpWidget(_buildSubject(serviceProvider: provider));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Λίστα'));
    await tester.pumpAndSettle();

    expect(find.text('Κάλυψη (2)'), findsOneWidget);
    expect(find.text('Εκπαίδευση (1)'), findsOneWidget);
  });

  // Test 4: Tapping a tab filters the list view
  testWidgets('tapping a type tab filters the list view', (tester) async {
    final provider = _FakeServiceProvider(
      fakeServices: [
        _makeService(1, 'Coverage Service', serviceType: {'id': 10, 'name': 'Κάλυψη'}),
        _makeService(2, 'Training Service', serviceType: {'id': 20, 'name': 'Εκπαίδευση'}),
      ],
    );

    await tester.pumpWidget(_buildSubject(serviceProvider: provider));
    await tester.pumpAndSettle();

    // Switch to List view (tab index 0: 'Λίστα')
    await tester.tap(find.text('Λίστα'));
    await tester.pumpAndSettle();

    // Both type tabs should be visible.
    expect(find.text('Κάλυψη (1)'), findsOneWidget);
    expect(find.text('Εκπαίδευση (1)'), findsOneWidget);

    // Tap the 'Κάλυψη (1)' type tab to filter.
    await tester.tap(find.text('Κάλυψη (1)'));
    await tester.pumpAndSettle();

    // Coverage Service should be visible; Training Service should be hidden.
    expect(find.text('Coverage Service'), findsOneWidget);
    expect(find.text('Training Service'), findsNothing);
  });
}
