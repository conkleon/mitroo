import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    try {
      final res = await ApiClient().post('/auth/forgot-password', body: {
        'email': _emailCtrl.text.trim(),
      });
      if (res.statusCode == 200) {
        setState(() => _sent = true);
      } else {
        final data = jsonDecode(res.body);
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
            child: _sent ? _buildSuccess(tt, cs) : _buildForm(tt, cs),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccess(TextTheme tt, ColorScheme cs) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.mark_email_read_outlined, size: 64, color: const Color(0xFF059669)),
        const SizedBox(height: 16),
        Text('Ελέγξτε το email σας', style: GoogleFonts.playfairDisplay(fontSize: 28, fontWeight: FontWeight.w700, color: const Color(0xFF1A1C1E))),
        const SizedBox(height: 8),
        Text(
          'Αν υπάρχει λογαριασμός με αυτό το email, θα λάβετε οδηγίες επαναφοράς κωδικού.',
          style: GoogleFonts.spaceGrotesk(fontSize: 13, color: const Color(0xFF6B7280)),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        TextButton(
          onPressed: () => context.go('/login'),
          child: const Text('Επιστροφή στη σύνδεση'),
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
          Text('Επαναφορά Κωδικού',
            style: GoogleFonts.playfairDisplay(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1C1E),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Εισάγετε το email του λογαριασμού σας.',
            style: GoogleFonts.spaceGrotesk(
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
            controller: _emailCtrl,
            decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
            keyboardType: TextInputType.emailAddress,
            validator: (v) => (v == null || !v.contains('@')) ? 'Εισάγετε έγκυρο email' : null,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Αποστολή', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
