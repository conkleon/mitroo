import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String token;
  const ResetPasswordScreen({super.key, required this.token});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    try {
      final res = await ApiClient().post('/auth/reset-password', body: {
        'token': widget.token,
        'password': _passwordCtrl.text,
      });
      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        setState(() => _done = true);
      } else {
        setState(() => _error = data['error'] ?? 'Αποτυχία');
      }
    } catch (e) {
      setState(() => _error = 'Σφάλμα σύνδεσης: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: _done ? _buildSuccess(tt, cs) : _buildForm(tt, cs),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccess(TextTheme tt, ColorScheme cs) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle_outline, size: 64, color: Color(0xFF059669)),
        const SizedBox(height: 16),
        Text('Ο κωδικός άλλαξε!', style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w700, color: const Color(0xFF1A1C1E))),
        const SizedBox(height: 8),
        Text(
          'Μπορείτε τώρα να συνδεθείτε με τον νέο κωδικό σας.',
          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF6B7280)),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton(
            onPressed: () => context.go('/login'),
            child: const Text('Σύνδεση', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _buildForm(TextTheme tt, ColorScheme cs) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Νέος Κωδικός',
            style: GoogleFonts.inter(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1C1E),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Εισάγετε τον νέο κωδικό πρόσβασής σας.',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: const Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 28),
          if (_error != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Text(_error!, style: TextStyle(color: const Color(0xFFDC2626), fontSize: 13)),
            ),
          TextFormField(
            controller: _passwordCtrl,
            decoration: const InputDecoration(labelText: 'Νέος κωδικός', prefixIcon: Icon(Icons.lock_outline)),
            obscureText: true,
            validator: (v) => (v == null || v.length < 8) ? 'Τουλάχιστον 8 χαρακτήρες' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _confirmCtrl,
            decoration: const InputDecoration(labelText: 'Επιβεβαίωση κωδικού', prefixIcon: Icon(Icons.lock_outline)),
            obscureText: true,
            validator: (v) => v != _passwordCtrl.text ? 'Οι κωδικοί δεν ταιριάζουν' : null,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Αλλαγή κωδικού', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.go('/login'),
            child: const Text('Επιστροφή στη σύνδεση'),
          ),
        ],
      ),
    );
  }
}
