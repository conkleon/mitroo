import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../helpers/chat_models.dart';

class DirectMessagePickerScreen extends StatefulWidget {
  const DirectMessagePickerScreen({super.key});

  @override
  State<DirectMessagePickerScreen> createState() =>
      _DirectMessagePickerScreenState();
}

class _DirectMessagePickerScreenState
    extends State<DirectMessagePickerScreen> {
  List<DmCandidateGroup> _groups = [];
  bool _loading = true;
  bool _creating = false;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final groups = await context.read<ChatProvider>().fetchDmCandidates();
    if (mounted) setState(() { _groups = groups; _loading = false; });
  }

  List<DmCandidateGroup> get _filtered {
    if (_searchQuery.isEmpty) return _groups;
    final q = _searchQuery.toLowerCase();
    return _groups
        .map((g) => DmCandidateGroup(
              departmentId: g.departmentId,
              departmentName: g.departmentName,
              users: g.users
                  .where((u) => u.fullName.toLowerCase().contains(q))
                  .toList(),
            ))
        .where((g) => g.users.isNotEmpty)
        .toList();
  }

  Future<void> _pick(DmCandidate candidate) async {
    if (_creating) return;
    setState(() => _creating = true);
    final chatId =
        await context.read<ChatProvider>().createDirectChat(candidate.id);
    if (!mounted) return;
    setState(() => _creating = false);
    if (chatId != null) {
      context.pop();
      context.push('/chat/$chatId');
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'missionAdmin':
        return 'Διαχ. Αποστολών';
      case 'itemAdmin':
        return 'Διαχ. Αντικειμένων';
      case 'volunteer':
        return 'Εθελοντής';
      default:
        return role;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final groups = _filtered;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Νέο άμεσο μήνυμα'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Αναζήτηση...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (v) =>
                  setState(() => _searchQuery = v.trim().toLowerCase()),
            ),
          ),
          if (_creating)
            const LinearProgressIndicator()
          else
            const SizedBox(height: 2),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : groups.isEmpty
                    ? Center(
                        child: Text(
                          _searchQuery.isNotEmpty
                              ? 'Δεν βρέθηκαν αποτελέσματα'
                              : 'Δεν υπάρχουν διαθέσιμοι χρήστες',
                          style: tt.bodyLarge
                              ?.copyWith(color: const Color(0xFF6B7280)),
                        ),
                      )
                    : ListView.builder(
                        itemCount: groups.fold<int>(
                          0,
                          (sum, g) => sum + 1 + g.users.length,
                        ),
                        itemBuilder: (context, index) {
                          int offset = 0;
                          for (final group in groups) {
                            if (index == offset) {
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                                child: Text(
                                  group.departmentName.toUpperCase(),
                                  style: tt.labelSmall?.copyWith(
                                    color: const Color(0xFF9CA3AF),
                                    letterSpacing: 0.8,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              );
                            }
                            offset++;
                            final userIndex = index - offset;
                            if (userIndex < group.users.length) {
                              final candidate = group.users[userIndex];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: cs.primary.withAlpha(25),
                                  child: Text(
                                    candidate.forename.isNotEmpty
                                        ? candidate.forename[0].toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                        color: cs.primary,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                                title: Text(candidate.fullName),
                                subtitle: Text(_roleLabel(candidate.role)),
                                onTap: () => _pick(candidate),
                              );
                            }
                            offset += group.users.length;
                          }
                          return const SizedBox.shrink();
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
