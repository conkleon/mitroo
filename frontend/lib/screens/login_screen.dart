import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  String? _error;
  bool _isRegister = false;
  final _forenameCtrl = TextEditingController();
  final _surnameCtrl = TextEditingController();
  final _enameCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _forenameCtrl.dispose();
    _surnameCtrl.dispose();
    _enameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    String? err;
    if (_isRegister) {
      err = await auth.register(
        _emailCtrl.text.trim(),
        _passwordCtrl.text,
        _forenameCtrl.text.trim(),
        _surnameCtrl.text.trim(),
        _enameCtrl.text.trim(),
      );
    } else {
      err = await auth.login(_emailCtrl.text.trim(), _passwordCtrl.text);
    }
    if (err != null && mounted) {
      setState(() => _error = err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/logo.png', height: 72),
                  const SizedBox(height: 12),
                  Text('Mitroo', style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: cs.primary)),
                  const SizedBox(height: 4),
                  Text('Διαχείριση Οργανισμού', style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280))),
                  const SizedBox(height: 36),
                  if (_error != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
                    ),
                  if (_isRegister) ...[
                    TextFormField(
                      controller: _forenameCtrl,
                      decoration: const InputDecoration(labelText: 'Όνομα', prefixIcon: Icon(Icons.person_outline)),
                      validator: (v) => (v == null || v.isEmpty) ? 'Υποχρεωτικό' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _surnameCtrl,
                      decoration: const InputDecoration(labelText: 'Επώνυμο', prefixIcon: Icon(Icons.person_outline)),
                      validator: (v) => (v == null || v.isEmpty) ? 'Υποχρεωτικό' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _enameCtrl,
                      decoration: const InputDecoration(labelText: 'Κωδικός Μέλους', prefixIcon: Icon(Icons.badge_outlined)),
                      validator: (v) => (v == null || v.length < 2) ? 'Τουλάχιστον 2 χαρακτήρες' : null,
                    ),
                    const SizedBox(height: 14),
                  ],
                  TextFormField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => (v == null || !v.contains('@')) ? 'Εισάγετε έγκυρο email' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _passwordCtrl,
                    decoration: const InputDecoration(labelText: 'Κωδικός', prefixIcon: Icon(Icons.lock_outline)),
                    obscureText: true,
                    validator: (v) => (v == null || v.length < 4) ? 'Τουλάχιστον 4 χαρακτήρες' : null,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: auth.loading ? null : _submit,
                      child: auth.loading
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(_isRegister ? 'Εγγραφή' : 'Σύνδεση', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => setState(() {
                      _isRegister = !_isRegister;
                      _error = null;
                    }),
                    child: Text(_isRegister ? 'Έχετε ήδη λογαριασμό; Σύνδεση' : 'Δεν έχετε λογαριασμό; Εγγραφή'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
