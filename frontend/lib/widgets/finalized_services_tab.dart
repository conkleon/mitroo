import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/sync_provider.dart';
import '../services/api_client.dart';
import 'service_card.dart';

class FinalizedServicesTab extends StatefulWidget {
  final int departmentId;
  final String departmentName;

  const FinalizedServicesTab({
    super.key,
    required this.departmentId,
    required this.departmentName,
  });

  @override
  State<FinalizedServicesTab> createState() => FinalizedServicesTabState();
}

class FinalizedServicesTabState extends State<FinalizedServicesTab>
    with AutomaticKeepAliveClientMixin {
  final _api = ApiClient();
  List<dynamic> _services = [];
  bool _loading = true;
  final Set<int> _syncingServiceIds = {};
  bool _isSyncing = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  static const int _limit = 20;
  final Set<int> _expandedCards = {};
  String _search = '';
  DateTime? _dateFrom;
  DateTime? _dateTo;
  Timer? _debounceTimer;
  bool _filtering = false;
  int? _selectedServiceTypeId;
  bool _filtersExpanded = false;
  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  int get departmentId => widget.departmentId;

  @override
  void initState() {
    super.initState();
    _load();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FinalizedServicesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.departmentId != widget.departmentId) {
      _load();
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _load({bool silent = false}) async {
    setState(() {
      if (silent) { _filtering = true; } else { _loading = true; }
      _page = 1;
      _hasMore = true;
    });
    try {
      final res = await _api.get(_buildServicesUrl(page: 1));
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body) as List<dynamic>;
        _services = data;
        _hasMore = data.length >= _limit;
      }
    } catch (_) {}
    if (mounted) setState(() { _loading = false; _filtering = false; });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final nextPage = _page + 1;
    try {
      final res = await _api.get(_buildServicesUrl(page: nextPage));
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body) as List<dynamic>;
        _services.addAll(data);
        _page = nextPage;
        _hasMore = data.length >= _limit;
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingMore = false);
  }

  String _buildServicesUrl({int page = 1}) {
    final buf = StringBuffer(
      '/services?departmentId=${widget.departmentId}&includeEnrollments=true&includeExpired=true&lifecycleStatus=finalized&page=$page&limit=$_limit',
    );
    if (_search.isNotEmpty) buf.write('&search=${Uri.encodeComponent(_search)}');
    if (_dateFrom != null) buf.write('&fromDate=${_fmtDate(_dateFrom!)}');
    if (_dateTo != null) buf.write('&toDate=${_fmtEndOfDay(_dateTo!)}');
    return buf.toString();
  }

  static String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}T00:00:00.000';

  static String _fmtEndOfDay(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}T23:59:59.999';

  static String _fmtDisplay(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  void _onSearchChanged(String v) {
    setState(() => _search = v);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(
        const Duration(milliseconds: 400), () => _load(silent: true));
  }

  Future<void> _pickDateFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateFrom ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _dateFrom = picked);
    _load(silent: true);
  }

  Future<void> _pickDateTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateTo ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _dateTo = picked);
    _load(silent: true);
  }

  Widget _buildDateButton({
    required String label,
    required bool isSet,
    required VoidCallback onTap,
    required VoidCallback onClear,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isSet
              ? const Color(0xFF7C3AED).withAlpha(15)
              : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSet
                ? const Color(0xFF7C3AED).withAlpha(60)
                : const Color(0xFFE5E7EB),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 14,
                color: isSet
                    ? const Color(0xFF7C3AED)
                    : const Color(0xFF6B7280)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isSet
                      ? const Color(0xFF7C3AED)
                      : const Color(0xFF6B7280),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSet)
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close,
                    size: 14, color: Color(0xFF7C3AED)),
              ),
          ],
        ),
      ),
    );
  }

  List<dynamic> get _filtered {
    if (_selectedServiceTypeId == null) return _services;
    return _services.where((s) {
      final st = s['serviceType'] as Map<String, dynamic>?;
      return st?['id'] == _selectedServiceTypeId;
    }).toList();
  }

  List<Map<String, dynamic>> get _allServiceTypes {
    final seen = <int>{};
    final types = <Map<String, dynamic>>[];
    for (final svc in _services) {
      final st = svc['serviceType'] as Map<String, dynamic>?;
      if (st == null) continue;
      final id = st['id'] as int?;
      if (id != null && seen.add(id)) types.add(st);
    }
    return types;
  }

  Future<void> _syncSingleService(int serviceId) async {
    setState(() => _syncingServiceIds.add(serviceId));
    try {
      await _api.post('/services/$serviceId/sync', body: {});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Αποτυχία συγχρονισμού υπηρεσίας')),
        );
      }
    } finally {
      setState(() => _syncingServiceIds.remove(serviceId));
      _load();
    }
  }

  Future<void> reload() async {
    await _load();
  }

  Future<void> sync() async {
    if (_isSyncing) return;
    if (mounted) setState(() => _isSyncing = true);
    try {
      final sync = context.read<SyncProvider>();
      await sync.syncFinalized(widget.departmentId);
    } catch (_) {}
    if (mounted) {
      setState(() => _isSyncing = false);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final filtered = _filtered;
    final serviceTypes = _allServiceTypes;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Αναζήτηση υπηρεσιών...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                  onChanged: _onSearchChanged,
                ),
              ),
              if (serviceTypes.isNotEmpty) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () =>
                      setState(() => _filtersExpanded = !_filtersExpanded),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: (_filtersExpanded ||
                              _selectedServiceTypeId != null)
                          ? const Color(0xFF7C3AED).withAlpha(15)
                          : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (_filtersExpanded ||
                                _selectedServiceTypeId != null)
                            ? const Color(0xFF7C3AED).withAlpha(60)
                            : const Color(0xFFE5E7EB),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.tune_rounded,
                          size: 16,
                          color: (_filtersExpanded ||
                                  _selectedServiceTypeId != null)
                              ? const Color(0xFF7C3AED)
                              : const Color(0xFF6B7280),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _selectedServiceTypeId != null
                              ? 'Φίλτρα (1)'
                              : 'Φίλτρα',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: (_filtersExpanded ||
                                    _selectedServiceTypeId != null)
                                ? const Color(0xFF7C3AED)
                                : const Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: (_filtersExpanded && serviceTypes.isNotEmpty)
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemCount: serviceTypes.length,
                      itemBuilder: (context, i) {
                        final st = serviceTypes[i];
                        final stId = st['id'] as int;
                        final selected = _selectedServiceTypeId == stId;
                        return GestureDetector(
                          onTap: () => setState(() {
                            _selectedServiceTypeId = selected ? null : stId;
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFF7C3AED)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: selected
                                    ? const Color(0xFF7C3AED)
                                    : const Color(0xFFD1D5DB),
                              ),
                            ),
                            child: Text(
                              st['name'] ?? '',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: selected
                                    ? Colors.white
                                    : const Color(0xFF374151),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: _buildDateButton(
                  label: _dateFrom != null ? _fmtDisplay(_dateFrom!) : 'Από ημερομηνία',
                  isSet: _dateFrom != null,
                  onTap: _pickDateFrom,
                  onClear: () {
                    setState(() => _dateFrom = null);
                    _load(silent: true);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDateButton(
                  label: _dateTo != null ? _fmtDisplay(_dateTo!) : 'Έως ημερομηνία',
                  isSet: _dateTo != null,
                  onTap: _pickDateTo,
                  onClear: () {
                    setState(() => _dateTo = null);
                    _load(silent: true);
                  },
                ),
              ),
            ],
          ),
        ),
        if (_filtering)
          const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: (filtered.isEmpty && !_hasMore)
              ? Center(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.inbox,
                            size: 64, color: Color(0xFFD1D5DB)),
                        const SizedBox(height: 12),
                        Text('Δεν βρέθηκαν υπηρεσίες',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: const Color(0xFF6B7280))),
                      ]))
              : RefreshIndicator(
                  onRefresh: sync,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                    itemCount: filtered.length + (_hasMore ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (i >= filtered.length) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: _loadingMore
                              ? const Center(
                                  child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2)))
                              : Center(
                                  child: TextButton(
                                    onPressed: _loadMore,
                                    child: const Text('Φόρτωση περισσότερων'),
                                  ),
                                ),
                        );
                      }
                      final svc = filtered[i] as Map<String, dynamic>;
                      final id = svc['id'] as int;
                      return ServiceCard(
                        service: svc,
                        isExpanded: _expandedCards.contains(id),
                        onToggleExpand: () => setState(() {
                          _expandedCards.contains(id)
                              ? _expandedCards.remove(id)
                              : _expandedCards.add(id);
                        }),
                        onOpenDetail: () => context.push('/admin/services/$id'),
                        onSync: () => _syncSingleService(id),
                        isSyncing: _syncingServiceIds.contains(id),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}
