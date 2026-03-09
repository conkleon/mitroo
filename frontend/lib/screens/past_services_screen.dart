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
  bool _specsLoading = true;
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
        setState(() {
          _specializations = jsonDecode(res.body);
          _specsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _specsLoading = false);
    }
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
      helpText: isFrom ? 'Select start date' : 'Select end date',
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
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text('Past Services — ${widget.departmentName}',
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
                    hintText: 'Search past services...',
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

              // ── Filters row ──
              Padding(
                padding: EdgeInsets.symmetric(horizontal: hPad),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Specialization dropdown
                    _buildSpecDropdown(tt),

                    // From date
                    _buildDateChip(
                      label: _fromDate != null
                          ? 'From: ${_fmtDay(_fromDate!)}'
                          : 'From date',
                      isSet: _fromDate != null,
                      onTap: () => _pickDate(isFrom: true),
                      onClear: _fromDate != null
                          ? () {
                              setState(() => _fromDate = null);
                              _load();
                            }
                          : null,
                    ),

                    // To date
                    _buildDateChip(
                      label: _toDate != null
                          ? 'To: ${_fmtDay(_toDate!)}'
                          : 'To date',
                      isSet: _toDate != null,
                      onTap: () => _pickDate(isFrom: false),
                      onClear: _toDate != null
                          ? () {
                              setState(() => _toDate = null);
                              _load();
                            }
                          : null,
                    ),

                    // Clear all filters
                    if (_selectedSpecId != null || _fromDate != null || _toDate != null)
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _selectedSpecId = null;
                            _fromDate = null;
                            _toDate = null;
                          });
                          _load();
                        },
                        icon: const Icon(Icons.clear_all, size: 18),
                        label: const Text('Clear filters'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // ── Results count ──
              Padding(
                padding: EdgeInsets.symmetric(horizontal: hPad),
                child: Row(children: [
                  Text(
                    _loading
                        ? 'Loading...'
                        : '${filtered.length} past service${filtered.length == 1 ? '' : 's'} found',
                    style: tt.bodySmall?.copyWith(color: Colors.grey.shade600),
                  ),
                ]),
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
                                      color: Colors.grey.shade300),
                                  const SizedBox(height: 12),
                                  Text('No past services found',
                                      style: tt.bodyLarge?.copyWith(
                                          color: Colors.grey.shade500)),
                                  const SizedBox(height: 4),
                                  Text('Try adjusting your filters',
                                      style: tt.bodySmall?.copyWith(
                                          color: Colors.grey.shade400)),
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

  Widget _buildSpecDropdown(TextTheme tt) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _selectedSpecId != null
            ? const Color(0xFF2563EB).withAlpha(15)
            : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _selectedSpecId != null
              ? const Color(0xFF2563EB)
              : Colors.grey.shade300,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: _selectedSpecId,
          hint: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.school, size: 16, color: Colors.grey.shade500),
              const SizedBox(width: 6),
              const Text('Specialization',
                  style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
            ],
          ),
          isDense: true,
          borderRadius: BorderRadius.circular(12),
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text('All specializations',
                  style: TextStyle(fontSize: 13)),
            ),
            if (!_specsLoading)
              ..._specializations.map((s) => DropdownMenuItem<int?>(
                    value: s['id'] as int,
                    child: Text(s['name'] ?? '',
                        style: const TextStyle(fontSize: 13)),
                  )),
          ],
          onChanged: (v) {
            setState(() => _selectedSpecId = v);
            _load();
          },
        ),
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
                : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today,
                size: 14,
                color: isSet
                    ? const Color(0xFF7C3AED)
                    : Colors.grey.shade500),
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
    final enrolledCount = (svc['_count']?['userServices'] ?? 0) as int;
    final visSpecs = svc['visibility'] as List<dynamic>? ?? [];
    final userServices = svc['userServices'] as List<dynamic>? ?? [];
    final acceptedCount =
        userServices.where((us) => us['status'] == 'accepted').length;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/admin/services/${svc['id']}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: name + completed badge
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
                    color: const Color(0xFF6B7280).withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('Completed',
                      style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 8),

              // Info chips
              Wrap(spacing: 12, runSpacing: 4, children: [
                if (location.isNotEmpty)
                  _PastInfoChip(Icons.location_on, location),
                if (carrier.isNotEmpty)
                  _PastInfoChip(Icons.groups, carrier),
                _PastInfoChip(
                    Icons.calendar_today, _fmtDate(svc['startAt'])),
              ]),

              if (visSpecs.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: visSpecs
                      .map((v) => Chip(
                            label: Text(
                                v['specialization']?['name'] ?? '',
                                style: const TextStyle(fontSize: 10)),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            labelPadding:
                                const EdgeInsets.symmetric(horizontal: 6),
                          ))
                      .toList(),
                ),
              ],
              const SizedBox(height: 8),

              // Bottom row: enrollment info
              Row(children: [
                Icon(Icons.people, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text('$enrolledCount enrolled',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600)),
                if (acceptedCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF059669).withAlpha(15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFF059669).withAlpha(50)),
                    ),
                    child: Text('$acceptedCount accepted',
                        style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF059669),
                            fontWeight: FontWeight.w600)),
                  ),
                ],
                const Spacer(),
                Icon(Icons.chevron_right,
                    size: 18, color: Colors.grey.shade400),
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
