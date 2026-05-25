import 'dart:convert';
import 'package:flutter/material.dart';
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
  bool _isSyncing = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  static const int _limit = 20;
  final Set<int> _expandedCards = {};
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _page = 1;
      _hasMore = true;
    });
    try {
      final res = await _api.get(
          '/services?departmentId=${widget.departmentId}&includeEnrollments=true&includeExpired=true&lifecycleStatus=finalized&page=1&limit=$_limit');
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body) as List<dynamic>;
        _services = data;
        _hasMore = data.length >= _limit;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final nextPage = _page + 1;
    try {
      final res = await _api.get(
          '/services?departmentId=${widget.departmentId}&includeEnrollments=true&includeExpired=true&lifecycleStatus=finalized&page=$nextPage&limit=$_limit');
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body) as List<dynamic>;
        _services.addAll(data);
        _page = nextPage;
        _hasMore = data.length >= _limit;
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingMore = false);
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

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Expanded(
          child: _services.isEmpty
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
                    itemCount: _services.length + (_hasMore ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (i >= _services.length) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: _loadingMore
                              ? const Center(
                                  child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child:
                                          CircularProgressIndicator(
                                              strokeWidth: 2)))
                              : Center(
                                  child: TextButton(
                                    onPressed: _loadMore,
                                    child: const Text('Φόρτωση περισσότερων'),
                                  ),
                                ),
                        );
                      }
                      final svc = _services[i] as Map<String, dynamic>;
                      final id = svc['id'] as int;
                      return ServiceCard(
                        service: svc,
                        isExpanded: _expandedCards.contains(id),
                        onToggleExpand: () => setState(() {
                          _expandedCards.contains(id)
                              ? _expandedCards.remove(id)
                              : _expandedCards.add(id);
                        }),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}
