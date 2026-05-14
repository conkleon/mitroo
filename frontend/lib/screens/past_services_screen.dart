import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../services/api_client.dart';

/// Shows past (completed) services with search, specialization filter,
/// and date-range filter.
class PastServicesScreen extends StatefulWidget {
  final int departmentId;
  final String departmentName;

  const PastServicesScreen({
    super.key,
    required this.departmentId,
    required this.departmentName,
  });

  @override
  State<PastServicesScreen> createState() => _PastServicesScreenState();
}

class _PastServicesScreenState extends State<PastServicesScreen> {
  final _api = ApiClient();

  List<dynamic> _services = [];
  List<dynamic> _specializations = [];
  bool _loading = true;
  String _search = '';
  int? _selectedSpecId;
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void initState() {
    super.initState();
    _loadSpecs();
    _load();
  }

  Future<void> _loadSpecs() async {
    try {
      final res = await _api.get('/specializations');
      if (res.statusCode == 200 && mounted) {
        setState(() => _specializations = jsonDecode(res.body));
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final params = <String, String>{
        'departmentId': '${widget.departmentId}',
        'pastOnly': 'true',
        'includeEnrollments': 'true',
      };
      if (_selectedSpecId != null) {
        params['specializationId'] = '$_selectedSpecId';
      }
      if (_fromDate != null) {
        params['fromDate'] = _fromDate!.toUtc().toIso8601String();
      }
      if (_toDate != null) {
        // End of the selected day
        final eod = DateTime(_toDate!.year, _toDate!.month, _toDate!.day, 23, 59, 59);
        params['toDate'] = eod.toUtc().toIso8601String();
      }

      final query = params.entries.map((e) => '${e.key}=${e.value}').join('&');
      final res = await _api.get('/services?$query');
      if (res.statusCode == 200 && mounted) {
        _services = jsonDecode(res.body);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  List<dynamic> get _filtered {
    if (_search.isEmpty) return _services;
    final q = _search.toLowerCase();
    return _services.where((s) {
      final name = (s['name'] ?? '').toString().toLowerCase();
      final loc = (s['location'] ?? '').toString().toLowerCase();
      final carrier = (s['carrier'] ?? '').toString().toLowerCase();
      final desc = (s['description'] ?? '').toString().toLowerCase();
      return name.contains(q) ||
          loc.contains(q) ||
          carrier.contains(q) ||
          desc.contains(q);
    }).toList();
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '—';
    return DateFormat('dd/MM/yy HH:mm').format(dt.toLocal());
  }

  String _fmtDay(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _fromDate : _toDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: isFrom ? 'Επιλέξτε ημ/νία έναρξης' : 'Επιλέξτε ημ/νία λήξης',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
      } else {
        _toDate = picked;
      }
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final filtered = _filtered;

    return Scaffold(
      appBar: AppBar(
        title: Text('Παλαιότερες Υπηρεσίες — ${widget.departmentName}',
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          final isWide = box.maxWidth >= 800;
          final hPad = isWide ? 32.0 : 16.0;

          return Column(
            children: [
              // ── Search bar ──
              Padding(
                padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 8),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Αναζήτηση παλαιοτέρων...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),

              // ── Filter strip ──
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: hPad),
                  children: [
                    ..._specializations.map((s) {
                      final specId = s['id'] as int;
                      final selected = _selectedSpecId == specId;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          avatar: Icon(Icons.workspace_premium,
                              size: 14,
                              color: selected
                                  ? const Color(0xFF7C3AED)
                                  : const Color(0xFF6B7280)),
                          label: Text(s['name'] ?? ''),
                          selected: selected,
                          onSelected: (_) {
                            setState(() =>
                                _selectedSpecId = selected ? null : specId);
                            _load();
                          },
                          selectedColor: const Color(0xFFF5F3FF),
                          checkmarkColor: const Color(0xFF7C3AED),
                          side: BorderSide(
                              color: selected
                                  ? const Color(0xFFDDD6FE)
                                  : const Color(0xFFD1D5DB)),
                          visualDensity: VisualDensity.compact,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: selected
                                ? const Color(0xFF6D28D9)
                                : const Color(0xFF6B7280),
                          ),
                          padding: EdgeInsets.zero,
                        ),
                      );
                    }),
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _buildDateChip(
                        label: _fromDate != null
                            ? 'Από: ${_fmtDay(_fromDate!)}'
                            : 'Από ημ/νία',
                        isSet: _fromDate != null,
                        onTap: () => _pickDate(isFrom: true),
                        onClear: _fromDate != null
                            ? () {
                                setState(() => _fromDate = null);
                                _load();
                              }
                            : null,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _buildDateChip(
                        label: _toDate != null
                            ? 'Έως: ${_fmtDay(_toDate!)}'
                            : 'Έως ημ/νία',
                        isSet: _toDate != null,
                        onTap: () => _pickDate(isFrom: false),
                        onClear: _toDate != null
                            ? () {
                                setState(() => _toDate = null);
                                _load();
                              }
                            : null,
                      ),
                    ),
                    if (_selectedSpecId != null ||
                        _fromDate != null ||
                        _toDate != null)
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _selectedSpecId = null;
                            _fromDate = null;
                            _toDate = null;
                          });
                          _load();
                        },
                        icon: const Icon(Icons.clear_all, size: 16),
                        label: const Text('Καθαρισμός',
                            style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          foregroundColor: Color(0xFF4B5563),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding:
                    EdgeInsets.symmetric(horizontal: hPad, vertical: 2),
                child: Text(
                  _loading
                      ? 'Φόρτωση...'
                      : 'Βρέθηκαν ${filtered.length} υπηρεσίες',
                  style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280)),
                ),
              ),
              const SizedBox(height: 4),

              // ── Service cards ──
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : filtered.isEmpty
                        ? Center(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.history,
                                      size: 64,
                                      color: Color(0xFFD1D5DB)),
                                  const SizedBox(height: 12),
                                  Text('Δεν βρέθηκαν παλαιότερες',
                                      style: tt.bodyLarge?.copyWith(
                                          color: const Color(0xFF6B7280))),
                                  const SizedBox(height: 4),
                                  Text('Δοκιμάστε διαφορετικά φίλτρα',
                                      style: tt.bodySmall?.copyWith(
                                          color: const Color(0xFF9CA3AF))),
                                ]))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: isWide
                                ? _buildGrid(filtered)
                                : _buildList(filtered),
                          ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildDateChip({
    required String label,
    required bool isSet,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSet
              ? const Color(0xFF7C3AED).withAlpha(15)
              : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSet
                ? const Color(0xFF7C3AED)
                : const Color(0xFFD1D5DB),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today,
                size: 14,
                color: isSet
                    ? const Color(0xFF7C3AED)
                    : const Color(0xFF6B7280)),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                  fontSize: 13,
                  color: isSet
                      ? const Color(0xFF7C3AED)
                      : const Color(0xFF6B7280),
                  fontWeight: isSet ? FontWeight.w600 : FontWeight.w400,
                )),
            if (onClear != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close,
                    size: 14, color: const Color(0xFF7C3AED)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<dynamic> services) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: services.length,
      itemBuilder: (ctx, i) => _buildCard(services[i]),
    );
  }

  Widget _buildGrid(List<dynamic> services) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(32, 4, 32, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 2.0,
      ),
      itemCount: services.length,
      itemBuilder: (ctx, i) => _buildCard(services[i]),
    );
  }

  Widget _buildCard(Map<String, dynamic> svc) {
    final tt = Theme.of(context).textTheme;
    final name = svc['name'] ?? '';
    final location = svc['location'] ?? '';
    final carrier = svc['carrier'] ?? '';
    final visSpecs = svc['visibility'] as List<dynamic>? ?? [];
    final userServices = svc['userServices'] as List<dynamic>? ?? [];
    final enrolledCount = (svc['_count']?['userServices'] ?? 0) as int;
    final acceptedCount =
        userServices.where((us) => us['status'] == 'accepted').length;
    final totalHours = userServices.fold<int>(
        0, (sum, us) => sum + ((us['hours'] as int?) ?? 0));

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/admin/services/${svc['id']}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top row: name + completed badge ──
              Row(children: [
                Expanded(
                  child: Text(name,
                      style: tt.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('Ολοκληρωμένη',
                      style: TextStyle(
                          color: Color(0xFF4B5563),
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 8),

              // ── Info row: location, carrier, date range ──
              Wrap(spacing: 12, runSpacing: 4, children: [
                if (location.isNotEmpty)
                  _PastInfoChip(Icons.location_on, location),
                if (carrier.isNotEmpty)
                  _PastInfoChip(Icons.groups, carrier),
                _PastInfoChip(Icons.calendar_today,
                    '${_fmtDate(svc['startAt'])} → ${_fmtDate(svc['endAt'])}'),
              ]),

              // ── Specialization chips (horizontal scroll) ──
              if (visSpecs.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 26,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: visSpecs.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 4),
                    itemBuilder: (context, i) {
                      final specName =
                          visSpecs[i]['specialization']?['name'] ?? '';
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F3FF),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFDDD6FE)),
                        ),
                        child: Text(specName,
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF6D28D9))),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 10),

              // ── Stats row ──
              Row(children: [
                _StatPill(Icons.people, '$enrolledCount εγγ.',
                    const Color(0xFF6B7280)),
                const SizedBox(width: 8),
                if (acceptedCount > 0) ...[
                  _StatPill(Icons.check_circle_outline,
                      '$acceptedCount εγκ.', const Color(0xFF059669)),
                  const SizedBox(width: 8),
                ],
                if (totalHours > 0)
                  _StatPill(Icons.schedule, '${totalHours}h',
                      const Color(0xFF2563EB)),
                const Spacer(),
                Icon(Icons.chevron_right,
                    size: 18, color: Color(0xFF9CA3AF)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _PastInfoChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _PastInfoChip(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: const Color(0xFF6B7280)),
      const SizedBox(width: 4),
      Text(text,
          style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
    ]);
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatPill(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
