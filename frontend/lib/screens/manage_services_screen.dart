import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/active_services_tab.dart';
import '../widgets/closed_services_tab.dart';
import '../widgets/completed_services_tab.dart';
import '../widgets/finalized_services_tab.dart';

class ManageServicesScreen extends StatefulWidget {
  final int departmentId;
  final String departmentName;

  const ManageServicesScreen({
    super.key,
    required this.departmentId,
    required this.departmentName,
  });

  @override
  State<ManageServicesScreen> createState() => _ManageServicesScreenState();
}

class _ManageServicesScreenState extends State<ManageServicesScreen>
    with TickerProviderStateMixin {
  late final TabController _tabController;
  final _activeKey = GlobalKey<ActiveServicesTabState>();
  final _closedKey = GlobalKey<ClosedServicesTabState>();
  final _completedKey = GlobalKey<CompletedServicesTabState>();
  final _finalizedKey = GlobalKey<FinalizedServicesTabState>();
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _syncActiveTab() async {
    if (_isSyncing) return;
    if (mounted) setState(() => _isSyncing = true);
    try {
      final idx = _tabController.index;
      switch (idx) {
        case 0:
          await _activeKey.currentState?.sync();
          break;
        case 1:
          await _closedKey.currentState?.sync();
          break;
        case 2:
          await _completedKey.currentState?.sync();
          break;
        case 3:
          await _finalizedKey.currentState?.sync();
          break;
      }
    } catch (_) {}
    if (mounted) setState(() => _isSyncing = false);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.departmentName,
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isSyncing ? null : _syncActiveTab,
            tooltip: _isSyncing ? 'Συγχρονισμός...' : 'Ανανέωση',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: cs.primary,
          unselectedLabelColor: const Color(0xFF6B7280),
          indicatorColor: cs.primary,
          labelStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          unselectedLabelStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          tabs: const [
            Tab(text: 'Ενεργές'),
            Tab(text: 'Κλειστές'),
            Tab(text: 'Ολοκληρ/νες'),
            Tab(text: 'Οριστικ/νες'),
          ],
        ),
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              heroTag: 'manage_services_fab',
              onPressed: () async {
                await context.push(
                    '/admin/services/create?departmentId=${widget.departmentId}&departmentName=${Uri.encodeComponent(widget.departmentName)}');
                if (mounted) _activeKey.currentState?.sync();
              },
              icon: const Icon(Icons.add),
              label: const Text('Νέα Υπηρεσία'),
            )
          : null,
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            ActiveServicesTab(
              key: _activeKey,
              departmentId: widget.departmentId,
              departmentName: widget.departmentName,
            ),
            ClosedServicesTab(
              key: _closedKey,
              departmentId: widget.departmentId,
              departmentName: widget.departmentName,
            ),
            CompletedServicesTab(
              key: _completedKey,
              departmentId: widget.departmentId,
              departmentName: widget.departmentName,
            ),
            FinalizedServicesTab(
              key: _finalizedKey,
              departmentId: widget.departmentId,
              departmentName: widget.departmentName,
            ),
          ],
        ),
      ),
    );
  }
}
