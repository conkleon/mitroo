import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mitroo_frontend/screens/victims_screen.dart';
import 'package:mitroo_frontend/providers/victim_provider.dart';

class _FakeVictimProvider extends VictimProvider {
  final List<Map<String, dynamic>> _victims;
  final List<Map<String, dynamic>> _pending;

  _FakeVictimProvider({
    List<Map<String, dynamic>> victims = const [],
    List<Map<String, dynamic>> pending = const [],
  })  : _victims = victims,
        _pending = pending;

  @override
  List<Map<String, dynamic>> get victims => _victims;

  @override
  List<Map<String, dynamic>> get pendingVictims => _pending;

  @override
  bool get loading => false;

  @override
  int get totalPages => 1;

  @override
  int get currentPage => 1;

  @override
  Future<void> fetchVictims({
    int? serviceId,
    String? search,
    String? dateFrom,
    String? dateTo,
    String? status,
    int page = 1,
    int limit = 20,
  }) async {}
}

Widget _buildSubject(VictimProvider provider) {
  return ChangeNotifierProvider<VictimProvider>.value(
    value: provider,
    child: const MaterialApp(home: VictimsScreen()),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders Card widgets instead of DataTable', (tester) async {
    final provider = _FakeVictimProvider(
      victims: [
        {
          'id': 1,
          'name': 'Νικολάου Μαρία',
          'createdAt': '2026-05-20T10:00:00.000Z',
          'chiefComplaint': 'Δύσπνοια',
          'isFinalized': false,
        },
      ],
    );

    await tester.pumpWidget(_buildSubject(provider));
    await tester.pump();

    expect(find.byType(DataTable), findsNothing);
    expect(find.byType(Card), findsWidgets);
    expect(find.text('Νικολάου Μαρία'), findsOneWidget);
  });

  testWidgets('shows pending icon for unsynced victims', (tester) async {
    final provider = _FakeVictimProvider(
      pending: [
        {
          'id': -1,
          'name': 'Παπαδόπουλος Γεώργιος',
          '_isPending': true,
        },
      ],
    );

    await tester.pumpWidget(_buildSubject(provider));
    await tester.pump();

    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    expect(find.text('Παπαδόπουλος Γεώργιος'), findsOneWidget);
  });

  testWidgets('shows empty state when no victims', (tester) async {
    final provider = _FakeVictimProvider();

    await tester.pumpWidget(_buildSubject(provider));
    await tester.pump();

    expect(find.text('Δεν υπάρχουν περιστατικά'), findsOneWidget);
    expect(find.byType(Card), findsNothing);
  });
}
