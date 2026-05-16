import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/victim_provider.dart';

class VictimsScreen extends StatefulWidget {
  const VictimsScreen({super.key});

  @override
  State<VictimsScreen> createState() => _VictimsScreenState();
}

class _VictimsScreenState extends State<VictimsScreen> {
  final _searchCtrl = TextEditingController();
  String _status = 'all';
  DateTime? _dateFrom;
  DateTime? _dateTo;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _fetch());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _fetch({int page = 1}) {
    context.read<VictimProvider>().fetchVictims(
      search: _searchCtrl.text,
      dateFrom: _dateFrom != null
          ? '${_dateFrom!.year}-${_dateFrom!.month.toString().padLeft(2, '0')}-${_dateFrom!.day.toString().padLeft(2, '0')}'
          : null,
      dateTo: _dateTo != null
          ? '${_dateTo!.year}-${_dateTo!.month.toString().padLeft(2, '0')}-${_dateTo!.day.toString().padLeft(2, '0')}'
          : null,
      status: _status,
      page: page,
    );
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _fetch();
    });
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VictimProvider>();
    final victims = provider.victims;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Περιστατικά'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/victims/create'),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _fetch(),
        child: Column(
          children: [
            // ── Search bar ──────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Αναζήτηση...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchCtrl.clear();
                            _fetch();
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onChanged: _onSearchChanged,
              ),
            ),

            // ── Date range row ─────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: _DatePickerButton(
                      label: 'Από',
                      date: _dateFrom,
                      onPicked: (d) {
                        setState(() => _dateFrom = d);
                        _fetch();
                      },
                      onClear: () {
                        setState(() => _dateFrom = null);
                        _fetch();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DatePickerButton(
                      label: 'Έως',
                      date: _dateTo,
                      onPicked: (d) {
                        setState(() => _dateTo = d);
                        _fetch();
                      },
                      onClear: () {
                        setState(() => _dateTo = null);
                        _fetch();
                      },
                    ),
                  ),
                ],
              ),
            ),

            // ── Status filter chips ────────────
            _FilterRow(
              selected: _status,
              onChanged: (v) {
                setState(() => _status = v);
                _fetch();
              },
            ),

            const SizedBox(height: 4),

            // ── Table or loading/empty ─────────
            Expanded(
              child: provider.loading
                  ? const Center(child: CircularProgressIndicator())
                  : victims.isEmpty
                      ? Center(
                          child: Text(
                            'Δεν υπάρχουν περιστατικά',
                            style: GoogleFonts.inter(
                              color: const Color(0xFF6B7280),
                              fontSize: 15,
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: MediaQuery.of(context).size.width,
                            ),
                            child: DataTable(
                              headingRowColor: WidgetStateProperty.all(
                                const Color(0xFFF9FAFB),
                              ),
                              dataRowColor: WidgetStateProperty.resolveWith((states) {
                                if (states.contains(WidgetState.selected)) {
                                  return cs.primary.withAlpha(15);
                                }
                                return null;
                              }),
                              columnSpacing: 24,
                              horizontalMargin: 16,
                              columns: [
                                DataColumn(
                                  label: Text('Όνομα',
                                      style: tt.labelLarge?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF374151))),
                                ),
                                DataColumn(
                                  label: Text('Ημ/νία Καταγραφής',
                                      style: tt.labelLarge?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF374151))),
                                ),
                                DataColumn(
                                  label: Text('Κύριο Σύμπτωμα',
                                      style: tt.labelLarge?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF374151))),
                                ),
                              ],
                              rows: victims.asMap().entries.map((entry) {
                                final i = entry.key;
                                final v = entry.value;
                                final name = v['name'] as String? ?? 'Άγνωστο';
                                final chiefComplaint = v['chiefComplaint'] as String? ?? '';
                                return DataRow(
                                  color: i.isEven
                                      ? WidgetStateProperty.all(const Color(0xFFF9FAFB))
                                      : null,
                                  onSelectChanged: (_) => context.push('/victims/${v['id']}'),
                                  cells: [
                                    DataCell(
                                      Text(name,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF1F2937)),
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                    DataCell(
                                      Text(_formatDate(v['createdAt'] as String?),
                                          style: const TextStyle(color: Color(0xFF6B7280))),
                                    ),
                                    DataCell(
                                      Text(
                                        chiefComplaint.isNotEmpty ? chiefComplaint : '—',
                                        style: TextStyle(
                                          color: chiefComplaint.isNotEmpty
                                              ? const Color(0xFF374151)
                                              : const Color(0xFF9CA3AF),
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
            ),

            // ── Pagination ──────────────────────
            if (provider.totalPages > 1)
              _PaginationBar(
                currentPage: provider.currentPage,
                totalPages: provider.totalPages,
                onPageChanged: (p) => _fetch(page: p),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Date picker button ─────────────────────────────────

class _DatePickerButton extends StatelessWidget {
  final String label;
  final DateTime? date;
  final ValueChanged<DateTime> onPicked;
  final VoidCallback onClear;

  const _DatePickerButton({
    required this.label,
    required this.date,
    required this.onPicked,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2035),
          locale: const Locale('el'),
        );
        if (picked != null) onPicked(picked);
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, size: 15, color: cs.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                date != null
                    ? '${date!.day}/${date!.month}/${date!.year}'
                    : label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: date != null ? const Color(0xFF1F2937) : const Color(0xFF9CA3AF),
                ),
              ),
            ),
            if (date != null)
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close, size: 16, color: Color(0xFF9CA3AF)),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Status filter chips ────────────────────────────────

class _FilterRow extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _FilterRow({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _FilterChip(label: 'Όλα', value: 'all', selected: selected, onChanged: onChanged),
          const SizedBox(width: 8),
          _FilterChip(label: 'Ανοιχτά', value: 'open', selected: selected, onChanged: onChanged),
          const SizedBox(width: 8),
          _FilterChip(label: 'Οριστικοποιημένα', value: 'finalized', selected: selected, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String value;
  final String selected;
  final ValueChanged<String> onChanged;

  const _FilterChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final active = selected == value;
    return ChoiceChip(
      label: Text(label),
      selected: active,
      onSelected: (_) => onChanged(value),
      selectedColor: const Color(0xFFC62828),
      labelStyle: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: active ? Colors.white : const Color(0xFF1A1C1E),
      ),
    );
  }
}

// ── Pagination bar ─────────────────────────────────────

class _PaginationBar extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;

  const _PaginationBar({
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Build page number list (show max 7 with ellipsis)
    final pages = <int>[];
    if (totalPages <= 7) {
      for (int i = 1; i <= totalPages; i++) {
        pages.add(i);
      }
    } else {
      pages.add(1);
      if (currentPage > 3) pages.add(-1); // ellipsis
      for (int i = (currentPage - 1).clamp(2, totalPages - 1);
          i <= (currentPage + 1).clamp(2, totalPages - 1);
          i++) {
        pages.add(i);
      }
      if (currentPage < totalPages - 2) pages.add(-2); // ellipsis
      pages.add(totalPages);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _PageButton(
            icon: Icons.chevron_left,
            enabled: currentPage > 1,
            onTap: () => onPageChanged(currentPage - 1),
          ),
          ...pages.map((p) {
            if (p < 0) {
              return const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2),
                child: Text('…', style: TextStyle(color: Color(0xFF9CA3AF))),
              );
            }
            return _PageButton(
              label: '$p',
              active: p == currentPage,
              enabled: true,
              onTap: () => onPageChanged(p),
            );
          }),
          _PageButton(
            icon: Icons.chevron_right,
            enabled: currentPage < totalPages,
            onTap: () => onPageChanged(currentPage + 1),
          ),
        ],
      ),
    );
  }
}

class _PageButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  const _PageButton({
    this.label,
    this.icon,
    this.active = false,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox(
        width: 36,
        height: 36,
        child: Material(
          color: active ? cs.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(8),
            child: Center(
              child: icon != null
                  ? Icon(icon, size: 18,
                      color: enabled ? const Color(0xFF374151) : const Color(0xFFD1D5DB))
                  : Text(label!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: active
                            ? Colors.white
                            : enabled
                                ? const Color(0xFF374151)
                                : const Color(0xFFD1D5DB),
                      )),
            ),
          ),
        ),
      ),
    );
  }
}
