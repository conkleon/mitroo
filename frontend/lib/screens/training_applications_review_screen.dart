import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api_client.dart';

class TrainingApplicationsReviewScreen extends StatefulWidget {
  const TrainingApplicationsReviewScreen({super.key});

  @override
  State<TrainingApplicationsReviewScreen> createState() => _TrainingApplicationsReviewScreenState();
}

class _TrainingApplicationsReviewScreenState extends State<TrainingApplicationsReviewScreen> {
  final _api = ApiClient();
  bool _loading = true;
  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _training = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.get('/training-applications?status=submitted'),
        _api.get('/training-applications?status=training'),
      ]);

      if (results[0].statusCode == 200) {
        _pending = (jsonDecode(results[0].body) as List).cast<Map<String, dynamic>>();
      }
      if (results[1].statusCode == 200) {
        _training = (jsonDecode(results[1].body) as List).cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _acceptTraining(int id) async {
    final res = await _api.patch('/training-applications/$id/accept-training', body: {});
    if (!mounted) return;
    if (res.statusCode == 200) {
      _load();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Η αίτηση έγινε αποδεκτή για εκπαίδευση.')));
      return;
    }
    final err = jsonDecode(res.body)['error'] ?? 'Αποτυχία ενέργειας';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.toString())));
  }

  Future<void> _reject(int id) async {
    final notesCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Απόρριψη Αίτησης'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Προαιρετικά προσθέστε σημείωση.'),
            const SizedBox(height: 10),
            TextField(
              controller: notesCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Σημειώσεις', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Άκυρο')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Απόρριψη'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final body = <String, dynamic>{};
    if (notesCtrl.text.trim().isNotEmpty) body['reviewNotes'] = notesCtrl.text.trim();

    final res = await _api.patch('/training-applications/$id/reject', body: body);
    if (!mounted) return;
    if (res.statusCode == 200) {
      _load();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Η αίτηση απορρίφθηκε.')));
      return;
    }
    final err = jsonDecode(res.body)['error'] ?? 'Αποτυχία ενέργειας';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.toString())));
  }

  Future<void> _enableServices(int id) async {
    final res = await _api.patch('/training-applications/$id/enable-services', body: {});
    if (!mounted) return;
    if (res.statusCode == 200) {
      _load();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ο χρήστης ενεργοποιήθηκε και μπορεί να συνδεθεί στο σύστημα.')),
      );
      return;
    }
    final err = jsonDecode(res.body)['error'] ?? 'Αποτυχία ενεργοποίησης';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.toString())));
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          title: const Text('Αιτήσεις Εκπαίδευσης'),
          centerTitle: true,
          bottom: TabBar(
            tabs: [
              Tab(text: 'Νέες Αιτήσεις (${_pending.length})'),
              Tab(text: 'Σε Εκπαίδευση (${_training.length})'),
            ],
          ),
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildPendingTab(tt),
                  _buildTrainingTab(tt),
                ],
              ),
      ),
    );
  }

  Widget _buildPendingTab(TextTheme tt) {
    if (_pending.isEmpty) {
      return const Center(child: Text('Δεν υπάρχουν νέες αιτήσεις.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _pending.length,
      itemBuilder: (context, i) {
        final app = _pending[i];
        return _ApplicationCard(
          app: app,
          actions: [
            OutlinedButton(
              onPressed: () => _reject(app['id'] as int),
              child: const Text('Απόρριψη'),
            ),
            FilledButton(
              onPressed: () => _acceptTraining(app['id'] as int),
              child: const Text('Αποδοχή για Εκπαίδευση'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTrainingTab(TextTheme tt) {
    if (_training.isEmpty) {
      return const Center(child: Text('Δεν υπάρχουν χρήστες σε εκπαίδευση.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _training.length,
      itemBuilder: (context, i) {
        final app = _training[i];
        return _ApplicationCard(
          app: app,
          actions: [
            OutlinedButton(
              onPressed: () => _reject(app['id'] as int),
              child: const Text('Απόρριψη'),
            ),
            FilledButton.icon(
              onPressed: () => _enableServices(app['id'] as int),
              icon: const Icon(Icons.check_circle, size: 16),
              label: const Text('Enable Services'),
            ),
          ],
        );
      },
    );
  }
}

class _ApplicationCard extends StatelessWidget {
  final Map<String, dynamic> app;
  final List<Widget> actions;

  const _ApplicationCard({required this.app, required this.actions});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final dept = app['department'] as Map<String, dynamic>?;
    final spec = app['specialization'] as Map<String, dynamic>?;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${app['forename'] ?? ''} ${app['surname'] ?? ''}', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(app['email']?.toString() ?? '-', style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280))),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Badge(label: 'Τμήμα: ${dept?['name'] ?? '-'}'),
                _Badge(label: 'Ειδίκευση: ${spec?['name'] ?? '-'}'),
                _Badge(label: 'Τηλ: ${app['phonePrimary'] ?? '-'}'),
              ],
            ),
            if ((app['reviewNotes'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Σημείωση: ${app['reviewNotes']}', style: tt.bodySmall),
            ],
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: actions),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  const _Badge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
