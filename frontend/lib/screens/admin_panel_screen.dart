import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/department_provider.dart';
import '../providers/item_provider.dart';
import '../services/api_client.dart';
import 'user_detail_screen.dart';

// ─── Responsive breakpoints ───────────────────────────────
const double _kCompactWidth = 600;
const double _kMediumWidth = 900;

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int? _drawerDeptId;
  String _drawerDeptName = '';
  int? _drawerUserId;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      context.read<DepartmentProvider>().fetchDepartments();
      context.read<ItemProvider>().fetchItems();
    });
  }

  Future<void> _refresh() async {
    await Future.wait([
      context.read<DepartmentProvider>().fetchDepartments(),
      context.read<ItemProvider>().fetchItems(),
    ]);
  }

  /// All depts this user admins — deduped union of mission + item depts.
  List<Map<String, dynamic>> _adminDepts(
      AuthProvider auth, DepartmentProvider deptProv) {
    if (auth.isAdmin) return deptProv.departments.cast<Map<String, dynamic>>();
    final seen = <int>{};
    final result = <Map<String, dynamic>>[];
    for (final dept in [
      ...auth.missionAdminDepartments,
      ...auth.itemAdminDepartments,
    ]) {
      final id = dept['id'] as int;
      if (seen.add(id)) result.add(dept);
    }
    return result;
  }

  /// Admin roles this user holds in a specific department.
  Set<String> _rolesInDept(AuthProvider auth, int deptId) {
    if (auth.isAdmin) return {'missionAdmin', 'itemAdmin'};
    final depts = auth.user?['departments'] as List<dynamic>? ?? [];
    return depts
        .where((d) => d['department']?['id'] == deptId)
        .map((d) => d['role'] as String)
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final deptProv = context.watch<DepartmentProvider>();

    final isSysAdmin = auth.isAdmin;
    final depts = _adminDepts(auth, deptProv);

    String subtitle;
    if (isSysAdmin) {
      subtitle = 'Διαχειριστής Συστήματος';
    } else {
      final roles = <String>[];
      if (auth.isMissionAdmin) roles.add('Διαχειριστής Αποστολών');
      if (auth.isItemAdmin) roles.add('Διαχειριστής Υλικού');
      subtitle = roles.join(' · ');
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF5F7FA),
      endDrawer: _UserDrawer(
        deptId: _drawerDeptId,
        deptName: _drawerDeptName,
        selectedUserId: _drawerUserId,
        onUserSelected: (id) => setState(() => _drawerUserId = id),
        onBack: () => setState(() => _drawerUserId = null),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final isCompact = width < _kCompactWidth;
            final isWide = width >= _kMediumWidth;
            final hPad = isCompact ? 16.0 : (isWide ? 40.0 : 24.0);
            final contentWidth = math.min(width, 1200.0);

            return RefreshIndicator(
              onRefresh: _refresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                    hPad, isCompact ? 12 : 20, hPad, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: contentWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _HeaderBar(
                            subtitle: subtitle,
                            auth: auth,
                            isCompact: isCompact),
                        SizedBox(height: isCompact ? 16 : 28),

                        // ── System Management (sysAdmin only) ──
                        if (isSysAdmin) ...[
                          _SectionHeader(
                              icon: Icons.settings,
                              label: 'Διαχείρηση Συστήματος'),
                          const SizedBox(height: 12),
                          _ResponsiveTileGrid(
                            isWide: isWide,
                            isCompact: isCompact,
                            tiles: [
                              _AdminTileData(
                                icon: Icons.people,
                                iconColor: const Color(0xFFDC2626),
                                bgColor: const Color(0xFFFEE2E2),
                                title: 'Διαχείρηση Χρηστών',
                                subtitle:
                                    'Δημιουργία, επεξεργασία & ανάθεση ρόλων',
                                onTap: () => context.push('/admin/users'),
                              ),
                              _AdminTileData(
                                icon: Icons.business,
                                iconColor: const Color(0xFF7C3AED),
                                bgColor: const Color(0xFFEDE9FE),
                                title: 'Διαχείρηση Τμημάτων',
                                subtitle: 'Δημιουργία & ρύθμιση τμημάτων',
                                onTap: () =>
                                    context.push('/admin/departments'),
                              ),
                              _AdminTileData(
                                icon: Icons.school,
                                iconColor: const Color(0xFFD97706),
                                bgColor: const Color(0xFFFEF3C7),
                                title: 'Διαχείρηση Ειδικεύσεων',
                                subtitle:
                                    'Δημιουργία & ανάθεση ειδικεύσεων',
                                onTap: () =>
                                    context.push('/admin/specializations'),
                              ),
                            ],
                          ),
                          SizedBox(height: isCompact ? 20 : 28),
                        ],

                        // ── Department cards ──
                        if (depts.isEmpty && !isSysAdmin)
                          const _EmptyCard(
                              message: 'Κανένα τμήμα ανατεθειμένο')
                        else if (depts.isNotEmpty) ...[
                          _SectionHeader(
                              icon: Icons.domain, label: 'Τμήματα'),
                          const SizedBox(height: 12),
                          ...depts.map((dept) {
                            final deptId = dept['id'] as int;
                            final roles = _rolesInDept(auth, deptId);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _DeptAdminCard(
                                dept: dept,
                                roles: roles,
                                isCompact: isCompact,
                                onUsersTap: roles.contains('missionAdmin')
                                    ? () {
                                        setState(() {
                                          _drawerDeptId = deptId;
                                          _drawerDeptName =
                                              dept['name'] as String? ??
                                                  'Τμήμα';
                                          _drawerUserId = null;
                                        });
                                        _scaffoldKey.currentState
                                            ?.openEndDrawer();
                                      }
                                    : null,
                              ),
                            );
                          }),
                        ],

                        const SizedBox(height: 60),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── Data classes ──────────────────────────────────────────

class _AdminTileData {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _AdminTileData({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}

// ─── Header ───────────────────────────────────────────────

class _HeaderBar extends StatelessWidget {
  final String subtitle;
  final AuthProvider auth;
  final bool isCompact;

  const _HeaderBar({
    required this.subtitle,
    required this.auth,
    required this.isCompact,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(isCompact ? 8 : 10),
          decoration: BoxDecoration(
            color: cs.primary.withAlpha(25),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.admin_panel_settings,
              color: cs.primary, size: isCompact ? 24 : 28),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Πίνακας Διαχείρισης',
                  style: (isCompact ? tt.titleLarge : tt.headlineSmall)
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: tt.bodySmall
                      ?.copyWith(color: const Color(0xFF6B7280))),
            ],
          ),
        ),
        GestureDetector(
          onTap: () => context.push('/profile'),
          child: CircleAvatar(
            radius: isCompact ? 18 : 20,
            backgroundColor: cs.primary,
            child: Text(
              auth.displayName.isNotEmpty
                  ? auth.displayName[0].toUpperCase()
                  : 'A',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: isCompact ? 14 : 16),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Responsive tile grid ─────────────────────────────────

class _ResponsiveTileGrid extends StatelessWidget {
  final bool isWide;
  final bool isCompact;
  final List<_AdminTileData> tiles;

  const _ResponsiveTileGrid({
    required this.isWide,
    required this.isCompact,
    required this.tiles,
  });

  @override
  Widget build(BuildContext context) {
    if (isWide) {
      final crossCount = tiles.length <= 2 ? 2 : 3;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossCount,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 2.6,
        ),
        itemCount: tiles.length,
        itemBuilder: (ctx, i) =>
            _AdminTileCard(data: tiles[i], isCompact: false),
      );
    }

    return Column(
      children: tiles
          .map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _AdminTileCard(data: t, isCompact: isCompact),
              ))
          .toList(),
    );
  }
}

// ─── Helper widgets ────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: cs.primary),
        const SizedBox(width: 8),
        Text(label,
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _AdminTileCard extends StatefulWidget {
  final _AdminTileData data;
  final bool isCompact;

  const _AdminTileCard({required this.data, required this.isCompact});

  @override
  State<_AdminTileCard> createState() => _AdminTileCardState();
}

class _AdminTileCardState extends State<_AdminTileCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final d = widget.data;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        transform: Matrix4.identity()..scale(_hovering ? 1.01 : 1.0),
        transformAlignment: Alignment.center,
        child: Card(
          elevation: _hovering ? 4 : 1,
          shadowColor: Colors.black.withAlpha(_hovering ? 30 : 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: _hovering ? d.iconColor.withAlpha(60) : Colors.transparent,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: d.onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: widget.isCompact ? 14 : 18,
                vertical: widget.isCompact ? 12 : 16,
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(widget.isCompact ? 8 : 10),
                    decoration: BoxDecoration(
                      color: d.bgColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(d.icon,
                        color: d.iconColor,
                        size: widget.isCompact ? 22 : 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(d.title,
                            style: tt.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(d.subtitle,
                            style: tt.bodySmall?.copyWith(
                                color: const Color(0xFF6B7280)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right,
                      color: Colors.grey.shade400, size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String message;
  const _EmptyCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(message,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey)),
        ),
      ),
    );
  }
}

// ─── Dept admin card ──────────────────────────────────────

class _DeptAdminCard extends StatelessWidget {
  final Map<String, dynamic> dept;
  final Set<String> roles;
  final bool isCompact;
  final VoidCallback? onUsersTap;

  const _DeptAdminCard({
    required this.dept,
    required this.roles,
    required this.isCompact,
    this.onUsersTap,
  });

  @override
  Widget build(BuildContext context) {
    final deptName = dept['name'] as String? ?? 'Τμήμα';
    final deptId = dept['id'] as int;
    final isMission = roles.contains('missionAdmin');

    final tiles = <_AdminTileData>[
      if (isMission)
        _AdminTileData(
          icon: Icons.assignment_turned_in,
          iconColor: const Color(0xFF1D4ED8),
          bgColor: const Color(0xFFDBEAFE),
          title: 'Αιτήσεις Εκπαίδευσης',
          subtitle: 'Αποδοχή & ενεργοποίηση εκπαιδευόμενων',
          onTap: () => context.push('/admin/training-applications'),
        ),
      if (isMission)
        _AdminTileData(
          icon: Icons.miscellaneous_services,
          iconColor: const Color(0xFF059669),
          bgColor: const Color(0xFFD1FAE5),
          title: 'Υπηρεσίες',
          subtitle: 'Δημιουργία & διαχείριση υπηρεσιών',
          onTap: () => context.push(
              '/admin/services?departmentId=$deptId&departmentName=${Uri.encodeComponent(deptName)}'),
        ),
      if (isMission && onUsersTap != null)
        _AdminTileData(
          icon: Icons.people,
          iconColor: const Color(0xFFDC2626),
          bgColor: const Color(0xFFFEE2E2),
          title: 'Χρήστες',
          subtitle: 'Προβολή & επεξεργασία μελών τμήματος',
          onTap: onUsersTap!,
        ),
      _AdminTileData(
        icon: Icons.inventory_2,
        iconColor: const Color(0xFF7C3AED),
        bgColor: const Color(0xFFEDE9FE),
        title: 'Αντικείμενα',
        subtitle: 'Διαχείριση εξοπλισμού & κουτιών',
        onTap: () => context.go('/items?departmentId=$deptId'),
      ),
      _AdminTileData(
        icon: Icons.directions_car,
        iconColor: const Color(0xFFD97706),
        bgColor: const Color(0xFFFEF3C7),
        title: 'Οχήματα',
        subtitle: 'Διαχείριση στόλου & χιλιομέτρων',
        onTap: () => context.go('/vehicles'),
      ),
    ];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    deptName,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (isMission)
                  _RoleBadge(
                      label: 'Αποστολών',
                      color: const Color(0xFF059669)),
                if (roles.contains('itemAdmin') && !isMission)
                  _RoleBadge(
                      label: 'Υλικού',
                      color: const Color(0xFF7C3AED)),
              ],
            ),
          ),
          const Divider(height: 1),
          ...tiles.map((t) =>
              _CompactTileRow(data: t, isCompact: isCompact)),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _RoleBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _CompactTileRow extends StatefulWidget {
  final _AdminTileData data;
  final bool isCompact;
  const _CompactTileRow({required this.data, required this.isCompact});

  @override
  State<_CompactTileRow> createState() => _CompactTileRowState();
}

class _CompactTileRowState extends State<_CompactTileRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final tt = Theme.of(context).textTheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: d.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          color: _hovering
              ? const Color(0xFFF9FAFB)
              : Colors.transparent,
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: widget.isCompact ? 10 : 12,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: d.bgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    Icon(d.icon, color: d.iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.title,
                        style: tt.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    Text(d.subtitle,
                        style: tt.bodySmall?.copyWith(
                            color: const Color(0xFF6B7280))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: Colors.grey.shade400, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── User drawer ──────────────────────────────────────────

class _UserDrawer extends StatefulWidget {
  final int? deptId;
  final String deptName;
  final int? selectedUserId;
  final ValueChanged<int> onUserSelected;
  final VoidCallback onBack;

  const _UserDrawer({
    required this.deptId,
    required this.deptName,
    required this.selectedUserId,
    required this.onUserSelected,
    required this.onBack,
  });

  @override
  State<_UserDrawer> createState() => _UserDrawerState();
}

class _UserDrawerState extends State<_UserDrawer> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _users = [];
  bool _loading = false;
  String _search = '';
  int? _loadedDeptId;

  @override
  void initState() {
    super.initState();
    if (widget.deptId != null) _loadUsers();
  }

  @override
  void didUpdateWidget(covariant _UserDrawer old) {
    super.didUpdateWidget(old);
    if (widget.deptId != null && widget.deptId != _loadedDeptId) {
      _loadUsers();
    }
  }

  Future<void> _loadUsers() async {
    final deptId = widget.deptId;
    if (deptId == null) return;
    setState(() => _loading = true);
    try {
      final res = await _api.get('/users/stats');
      if (res.statusCode == 200 && mounted) {
        final all = (jsonDecode(res.body) as List)
            .cast<Map<String, dynamic>>();
        _users = all.where((u) {
          final depts = u['departments'] as List<dynamic>? ?? [];
          return depts
              .any((d) => d['department']?['id'] == deptId);
        }).toList();
        _loadedDeptId = deptId;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.isEmpty) return _users;
    final q = _search.toLowerCase();
    return _users.where((u) {
      final name =
          '${u['forename'] ?? ''} ${u['surname'] ?? ''}'.toLowerCase();
      final eame = (u['eame'] ?? '').toString().toLowerCase();
      return name.contains(q) || eame.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final inDetail = widget.selectedUserId != null;
    final screenWidth = MediaQuery.of(context).size.width;

    return Drawer(
      width: screenWidth < 600 ? screenWidth : 420,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(inDetail
                        ? Icons.arrow_back
                        : Icons.close),
                    onPressed: inDetail
                        ? widget.onBack
                        : () => Navigator.of(context).pop(),
                    tooltip: inDetail ? 'Πίσω' : 'Κλείσιμο',
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      inDetail
                          ? 'Στοιχεία Χρήστη'
                          : 'Χρήστες – ${widget.deptName}',
                      style: tt.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Content: user detail or user list
            Expanded(
              child: inDetail
                  ? Navigator(
                      onGenerateRoute: (_) => MaterialPageRoute(
                        builder: (_) =>
                            UserDetailBody(userId: widget.selectedUserId!),
                      ),
                    )
                  : _buildList(tt, cs),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(TextTheme tt, ColorScheme cs) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Αναζήτηση...',
              prefixIcon: Icon(Icons.search, size: 20),
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _filtered.isEmpty
                  ? Center(
                      child: Text('Κανένα αποτέλεσμα',
                          style: tt.bodyMedium
                              ?.copyWith(color: Colors.grey)),
                    )
                  : ListView.separated(
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 16),
                      itemBuilder: (ctx, i) {
                        final u = _filtered[i];
                        final name =
                            '${u['forename'] ?? ''} ${u['surname'] ?? ''}'
                                .trim();
                        final initial = name.isNotEmpty
                            ? name[0].toUpperCase()
                            : '?';
                        final depts = u['departments']
                                as List<dynamic>? ??
                            [];
                        final roleDept = depts.firstWhere(
                          (d) =>
                              d['department']?['id'] ==
                              widget.deptId,
                          orElse: () => <String, dynamic>{},
                        );
                        final role =
                            roleDept['role'] as String?;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: cs.primary,
                            child: Text(initial,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600)),
                          ),
                          title: Text(name,
                              style: tt.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500)),
                          subtitle: role != null
                              ? Text(_roleLabel(role),
                                  style: tt.bodySmall?.copyWith(
                                      color:
                                          const Color(0xFF6B7280)))
                              : null,
                          trailing: const Icon(
                              Icons.chevron_right,
                              size: 18),
                          onTap: () =>
                              widget.onUserSelected(u['id'] as int),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  String _roleLabel(String role) => switch (role) {
        'missionAdmin' => 'Διαχ. Αποστολών',
        'itemAdmin' => 'Διαχ. Υλικού',
        _ => 'Εθελοντής',
      };
}
