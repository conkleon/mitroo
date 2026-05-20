import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mitroo_frontend/screens/victim_detail_screen.dart';
import 'package:mitroo_frontend/providers/victim_provider.dart';
import 'package:mitroo_frontend/providers/auth_provider.dart';

// Fake VictimProvider — overrides only what the detail screen reads.
class _FakeVictimProvider extends VictimProvider {
  final Map<String, dynamic> _victim;

  _FakeVictimProvider(this._victim);

  @override
  Map<String, dynamic>? get selected => _victim;

  @override
  bool get loading => false;

  @override
  Future<void> fetchVictim(int id) async {}
}

// Fake AuthProvider — admin user so all three buttons are shown.
class _FakeAuthProvider extends AuthProvider {
  @override
  Map<String, dynamic>? get user => {'id': 1, 'isAdmin': true};

  @override
  bool get isAdmin => true;

  @override
  bool get isMissionAdmin => true;
}

Widget _buildSubject({
  required VictimProvider victimProvider,
  required AuthProvider authProvider,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<VictimProvider>.value(value: victimProvider),
      ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
    ],
    child: MaterialApp(
      home: VictimDetailScreen(victimId: 1),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows Edit, Finalize and Delete buttons for admin', (tester) async {
    final victim = {
      'id': 1,
      'name': 'Νικολάου Μαρία',
      'isFinalized': false,
      'createdById': 99,
      'vitalSigns': <dynamic>[],
      'treatments': <dynamic>[],
    };

    await tester.pumpWidget(_buildSubject(
      victimProvider: _FakeVictimProvider(victim),
      authProvider: _FakeAuthProvider(),
    ));
    await tester.pump();

    expect(find.text('Επεξεργασία'), findsOneWidget);
    expect(find.text('Οριστικοποίηση'), findsOneWidget);
    expect(find.text('Διαγραφή'), findsOneWidget);
  });

  testWidgets('Delete button is visible on a narrow screen', (tester) async {
    final victim = {
      'id': 1,
      'name': 'Νικολάου Μαρία',
      'isFinalized': false,
      'createdById': 99,
      'vitalSigns': <dynamic>[],
      'treatments': <dynamic>[],
    };

    // Simulate a narrow mobile screen (320 logical pixels wide)
    await tester.binding.setSurfaceSize(const Size(320, 600));

    await tester.pumpWidget(_buildSubject(
      victimProvider: _FakeVictimProvider(victim),
      authProvider: _FakeAuthProvider(),
    ));
    await tester.pump();

    // All three buttons must be visible even on a narrow screen
    expect(find.text('Επεξεργασία'), findsOneWidget);
    expect(find.text('Οριστικοποίηση'), findsOneWidget);
    expect(find.text('Διαγραφή'), findsOneWidget);
  });
}
