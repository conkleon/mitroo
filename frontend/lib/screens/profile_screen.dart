import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final name = auth.displayName.isNotEmpty ? auth.displayName : (user?['ename'] ?? 'User');
    final initials = name.split(' ').where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase()).take(2).join();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Profile'),
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
                      child: Text('Admin', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600, fontSize: 12)),
                    ),
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
                  Text('Details', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  _DetailRow(icon: Icons.badge_outlined, label: 'Identity Code', value: user?['ename'] ?? '-'),
                  const Divider(height: 24),
                  _DetailRow(icon: Icons.person_outline, label: 'First Name', value: user?['forename'] ?? '-'),
                  const Divider(height: 24),
                  _DetailRow(icon: Icons.person_outline, label: 'Last Name', value: user?['surname'] ?? '-'),
                  const Divider(height: 24),
                  _DetailRow(icon: Icons.email_outlined, label: 'Email', value: user?['email'] ?? '-'),
                  if (user?['phonePrimary'] != null) ...[
                    const Divider(height: 24),
                    _DetailRow(icon: Icons.phone_outlined, label: 'Phone', value: user?['phonePrimary'] ?? '-'),
                  ],
                  if (user?['address'] != null) ...[
                    const Divider(height: 24),
                    _DetailRow(icon: Icons.home_outlined, label: 'Address', value: user?['address'] ?? '-'),
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
                    Text('Departments', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
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

          // ── Sign out ──
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                auth.logout();
                context.go('/login');
              },
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Sign Out'),
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
