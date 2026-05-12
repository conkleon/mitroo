import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/sync_provider.dart';

class SyncConfigCard extends StatefulWidget {
  final int departmentId;
  const SyncConfigCard({super.key, required this.departmentId});

  @override
  State<SyncConfigCard> createState() => _SyncConfigCardState();
}

class _SyncConfigCardState extends State<SyncConfigCard> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _syncEnabled = false;
  bool _passwordObscured = true;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    final sync = context.read<SyncProvider>();
    await Future.wait([
      sync.loadConfig(widget.departmentId),
      sync.loadStatus(widget.departmentId),
    ]);
    final cfg = sync.config;
    if (cfg != null && cfg['configured'] == true && mounted) {
      setState(() {
        _usernameCtrl.text = cfg['username'] ?? '';
        _passwordCtrl.text = ''; // never pre-fill password
        _syncEnabled = cfg['syncEnabled'] == true;
        _initialized = true;
      });
    } else if (mounted) {
      setState(() => _initialized = true);
    }
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return 'Ποτέ';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      return DateFormat('d MMM HH:mm', 'el_GR').format(dt);
    } catch (_) {
      return raw.toString();
    }
  }

  Future<void> _save() async {
    final sync = context.read<SyncProvider>();
    final err = await sync.saveConfig(
      widget.departmentId,
      username: _usernameCtrl.text.trim(),
      password: _passwordCtrl.text,
      syncEnabled: _syncEnabled,
    );
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err), backgroundColor: Colors.red));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Αποθηκεύτηκε')),
      );
    }
  }

  Future<void> _triggerUserSync() async {
    final sync = context.read<SyncProvider>();
    final result = await sync.syncUsers(widget.departmentId);
    if (!mounted) return;
    if (result != null) {
      final created = result['created'] ?? 0;
      final updated = result['updated'] ?? 0;
      final errors = (result['errors'] as List?)?.length ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Χρήστες: +$created νέοι, $updated ενημερώθηκαν'
            '${errors > 0 ? ', $errors σφάλματα' : ''}'),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(sync.error ?? 'Αποτυχία συγχρονισμού'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _triggerServiceSync() async {
    final sync = context.read<SyncProvider>();
    final result = await sync.syncServices(widget.departmentId);
    if (!mounted) return;
    if (result != null) {
      final created = result['created'] ?? 0;
      final updated = result['updated'] ?? 0;
      final errors = (result['errors'] as List?)?.length ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Υπηρεσίες: +$created νέες, $updated ενημερώθηκαν'
            '${errors > 0 ? ', $errors σφάλματα' : ''}'),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(sync.error ?? 'Αποτυχία συγχρονισμού'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SyncProvider>(
      builder: (context, sync, _) {
        final status = sync.status;
        final lastUserSync = status?['lastUserSyncAt'];
        final lastServiceSync = status?['lastServiceSyncAt'];
        final lastStatus = status?['lastSyncStatus'];

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.sync, size: 20),
                    const SizedBox(width: 8),
                    Text('Συγχρονισμός Mitroo',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            )),
                    if (lastStatus != null) ...[
                      const SizedBox(width: 8),
                      Icon(
                        lastStatus == 'success' ? Icons.check_circle : Icons.error,
                        size: 16,
                        color: lastStatus == 'success' ? Colors.green : Colors.red,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                if (!_initialized)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  TextField(
                    controller: _usernameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Όνομα χρήστη (Mitroo)',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: _passwordObscured,
                    decoration: InputDecoration(
                      labelText: 'Κωδικός (Mitroo)',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_passwordObscured
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () =>
                            setState(() => _passwordObscured = !_passwordObscured),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Αυτόματος συγχρονισμός κατά τη σύνδεση'),
                    value: _syncEnabled,
                    onChanged: (v) => setState(() => _syncEnabled = v),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: sync.isSavingConfig ? null : _save,
                      child: sync.isSavingConfig
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Αποθήκευση'),
                    ),
                  ),
                  const Divider(height: 32),
                  _SyncRow(
                    label: 'Χρήστες',
                    lastSync: _formatDate(lastUserSync),
                    loading: sync.isSyncingUsers,
                    onSync: _triggerUserSync,
                  ),
                  const SizedBox(height: 8),
                  _SyncRow(
                    label: 'Υπηρεσίες',
                    lastSync: _formatDate(lastServiceSync),
                    loading: sync.isSyncingServices,
                    onSync: _triggerServiceSync,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SyncRow extends StatelessWidget {
  final String label;
  final String lastSync;
  final bool loading;
  final VoidCallback onSync;

  const _SyncRow({
    required this.label,
    required this.lastSync,
    required this.loading,
    required this.onSync,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
              Text('Τελευταίος: $lastSync',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: const Color(0xFF6B7280))),
            ],
          ),
        ),
        SizedBox(
          width: 130,
          child: OutlinedButton.icon(
            onPressed: loading ? null : onSync,
            icon: loading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync, size: 16),
            label: Text(loading ? 'Συγχρονισμός...' : 'Συγχρονισμός'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ),
      ],
    );
  }
}
