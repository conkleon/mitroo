import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _api = ApiClient();
  bool _loading = true;
  String? _error;

  // Hours data
  int _totalHours = 0;
  int _yearHours = 0;
  int _yearServiceHours = 0;
  int _yearVolHours = 0;
  int _yearTrainingHours = 0;
  int _yearTrainerHours = 0;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.get('/auth/me/profile');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _totalHours = data['totalHours'] ?? 0;
          _yearHours = data['yearHours'] ?? 0;
          _yearServiceHours = data['yearServiceHours'] ?? 0;
          _yearVolHours = data['yearVolHours'] ?? 0;
          _yearTrainingHours = data['yearTrainingHours'] ?? 0;
          _yearTrainerHours = data['yearTrainerHours'] ?? 0;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Αποτυχία φόρτωσης προφίλ';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Σφάλμα σύνδεσης';
        _loading = false;
      });
    }
  }

  // ── Change password dialog ──────────────────────
  Future<void> _showChangePasswordDialog() async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool busy = false;
    String? dialogError;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Αλλαγή Κωδικού'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dialogError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(dialogError!, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
                  ),
                TextFormField(
                  controller: currentCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Τρέχων Κωδικός',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? 'Υποχρεωτικό' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: newCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Νέος Κωδικός',
                    prefixIcon: Icon(Icons.lock_reset),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Υποχρεωτικό';
                    if (v.length < 8) return 'Τουλάχιστον 8 χαρακτήρες';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: confirmCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Επιβεβαίωση Κωδικού',
                    prefixIcon: Icon(Icons.lock_reset),
                  ),
                  validator: (v) {
                    if (v != newCtrl.text) return 'Οι κωδικοί δεν ταιριάζουν';
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('Άκυρο')),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() {
                        busy = true;
                        dialogError = null;
                      });
                      try {
                        final res = await _api.post('/auth/change-password', body: {
                          'currentPassword': currentCtrl.text,
                          'newPassword': newCtrl.text,
                        });
                        if (res.statusCode == 200) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Ο κωδικός άλλαξε επιτυχώς')),
                            );
                          }
                        } else {
                          final body = jsonDecode(res.body);
                          setDialogState(() {
                            dialogError = body['error'] ?? 'Αποτυχία αλλαγής κωδικού';
                            busy = false;
                          });
                        }
                      } catch (_) {
                        setDialogState(() {
                          dialogError = 'Σφάλμα σύνδεσης';
                          busy = false;
                        });
                      }
                    },
              child: busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Αλλαγή'),
            ),
          ],
        ),
      ),
    );
    currentCtrl.dispose();
    newCtrl.dispose();
    confirmCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final String name = auth.displayName.isNotEmpty ? auth.displayName : (user?['ename'] ?? 'Χρήστης').toString();
    final initials = name.split(' ').where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase()).take(2).join();
    final currentYear = DateTime.now().year;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Προφίλ'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Avatar & name card ──
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: cs.primary,
                    child: Text(
                      initials,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 28),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(name, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    user?['email'] ?? '',
                    style: tt.bodyMedium?.copyWith(color: const Color(0xFF6B7280)),
                  ),
                  if (auth.isAdmin) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDBEAFE),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('Διαχειριστής', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600, fontSize: 12)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Hours summary card ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.schedule, color: cs.primary, size: 22),
                      const SizedBox(width: 8),
                      Text('Ώρες', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_loading)
                    const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                  else if (_error != null)
                    Center(child: Text(_error!, style: TextStyle(color: Colors.red.shade600)))
                  else ...[
                    // Total hours (all time)
                    _HoursHighlight(label: 'Συνολικές Ώρες', hours: _totalHours, color: cs.primary),
                    const Divider(height: 24),
                    Text('Ανάλυση $currentYear',
                        style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: const Color(0xFF374151))),
                    const SizedBox(height: 12),
                    _HoursRow(label: 'Κάλυψη', hours: _yearServiceHours, icon: Icons.medical_services_outlined, color: const Color(0xFF2563EB)),
                    const SizedBox(height: 8),
                    _HoursRow(label: 'Εθελοντικές', hours: _yearVolHours, icon: Icons.volunteer_activism, color: const Color(0xFF059669)),
                    const SizedBox(height: 8),
                    _HoursRow(label: 'Επανεκπαίδευση', hours: _yearTrainingHours, icon: Icons.school_outlined, color: const Color(0xFFD97706)),
                    const SizedBox(height: 8),
                    _HoursRow(label: 'Εκπαιδευτές', hours: _yearTrainerHours, icon: Icons.co_present_outlined, color: const Color(0xFF7C3AED)),
                    const Divider(height: 24),
                    _HoursHighlight(label: 'Σύνολο $currentYear', hours: _yearHours, color: const Color(0xFF059669)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Details card ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Στοιχεία', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  _DetailRow(icon: Icons.badge_outlined, label: 'Κωδικός', value: user?['ename'] ?? '-'),
                  const Divider(height: 24),
                  _DetailRow(icon: Icons.person_outline, label: 'Όνομα', value: user?['forename'] ?? '-'),
                  const Divider(height: 24),
                  _DetailRow(icon: Icons.person_outline, label: 'Επώνυμο', value: user?['surname'] ?? '-'),
                  const Divider(height: 24),
                  _DetailRow(icon: Icons.email_outlined, label: 'Email', value: user?['email'] ?? '-'),
                  if (user?['phonePrimary'] != null) ...[
                    const Divider(height: 24),
                    _DetailRow(icon: Icons.phone_outlined, label: 'Τηλέφωνο', value: user?['phonePrimary'] ?? '-'),
                  ],
                  if (user?['address'] != null) ...[
                    const Divider(height: 24),
                    _DetailRow(icon: Icons.home_outlined, label: 'Διεύθυνση', value: user?['address'] ?? '-'),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Departments card ──
          if (user?['departments'] != null && (user!['departments'] as List).isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Τμήματα', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    ...(user['departments'] as List).map((d) {
                      final dept = d['department'];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: cs.primary.withAlpha(20),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.business, color: cs.primary, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(dept?['name'] ?? '', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w500)),
                                  Text(d['role'] ?? '', style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280))),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),

          // ── Change password ──
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _showChangePasswordDialog,
              icon: const Icon(Icons.lock_outline, size: 18),
              label: const Text('Αλλαγή Κωδικού'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Sign out ──
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                auth.logout();
                context.go('/login');
              },
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Αποσύνδεση'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade600,
                side: BorderSide(color: Colors.red.shade300),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Reusable widgets ──────────────────────────────

class _HoursHighlight extends StatelessWidget {
  final String label;
  final int hours;
  final Color color;
  const _HoursHighlight({required this.label, required this.hours, required this.color});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: color.withAlpha(25),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$hours h',
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: color),
          ),
        ),
      ],
    );
  }
}

class _HoursRow extends StatelessWidget {
  final String label;
  final int hours;
  final IconData icon;
  final Color color;
  const _HoursRow({required this.label, required this.hours, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withAlpha(25),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: tt.bodyMedium)),
        Text('$hours h', style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF6B7280)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280))),
              const SizedBox(height: 2),
              Text(value, style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }
}
