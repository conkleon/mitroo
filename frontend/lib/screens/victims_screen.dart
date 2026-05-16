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
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<VictimProvider>().fetchVictims());
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VictimProvider>();
    final victims = provider.victims;

    final filtered = _filter == 'all'
        ? victims
        : _filter == 'open'
            ? victims.where((v) => v['isFinalized'] != true).toList()
            : victims.where((v) => v['isFinalized'] == true).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Περιστατικά'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/victims/create'),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () => provider.fetchVictims(),
        child: Column(
          children: [
            _FilterRow(selected: _filter, onChanged: (v) => setState(() => _filter = v)),
            Expanded(
              child: provider.loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? Center(
                          child: Text(
                            _filter == 'all'
                                ? 'Δεν υπάρχουν περιστατικά'
                                : _filter == 'open'
                                    ? 'Δεν υπάρχουν ανοιχτά περιστατικά'
                                    : 'Δεν υπάρχουν οριστικοποιημένα περιστατικά',
                            style: GoogleFonts.inter(color: const Color(0xFF6B7280), fontSize: 15),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final v = filtered[index];
                            return _VictimCard(victim: v);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

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

class _VictimCard extends StatelessWidget {
  final Map<String, dynamic> victim;

  const _VictimCard({required this.victim});

  @override
  Widget build(BuildContext context) {
    final name = victim['name'] ?? 'Άγνωστο';
    final age = victim['age'];
    final isFinalized = victim['isFinalized'] == true;
    final createdAt = victim['createdAt'] as String?;
    final serviceName = (victim['service'] as Map<String, dynamic>?)?.let((s) => s['name']) ?? '—';
    final id = victim['id'] as int;

    String dateStr = '';
    if (createdAt != null) {
      final dt = DateTime.tryParse(createdAt)?.toLocal();
      if (dt != null) {
        dateStr = '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/victims/$id'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(name,
                            style: GoogleFonts.literata(fontSize: 15, fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isFinalized)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(Icons.lock, size: 14, color: const Color(0xFF6B7280)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [if (age != null) '$age ετών', serviceName].where((s) => s.isNotEmpty).join(' · '),
                      style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),
              Text(dateStr, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF9CA3AF))),
            ],
          ),
        ),
      ),
    );
  }
}

extension _MapLet on Map? {
  R? let<R>(R Function(Map m) fn) {
    final self = this;
    if (self == null) return null;
    return fn(self);
  }
}
