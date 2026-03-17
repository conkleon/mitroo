import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
  bool _obscurePassword = true;
  final _forenameCtrl = TextEditingController();
  final _surnameCtrl = TextEditingController();
  final _enameCtrl = TextEditingController();

  static const _primaryRed = Color(0xFFC62828);
  static const _subtleGray = Color(0xFF6B7280);

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
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      body: isDesktop ? _buildDesktopLayout(auth) : _buildMobileLayout(auth),
    );
  }

  Widget _buildDesktopLayout(AuthProvider auth) {
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: _buildBrandingPanel(),
        ),
        Expanded(
          flex: 4,
          child: Container(
            color: Colors.white,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 48),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _buildFormContent(auth, isDesktop: true),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(AuthProvider auth) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF0F2F5), Color(0xFFE8EBF0)],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildMobileHeader(),
                  const SizedBox(height: 28),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(15),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(28),
                    child: _buildFormContent(auth, isDesktop: false),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandingPanel() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFB71C1C), Color(0xFFC62828), Color(0xFFD32F2F)],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _CirclePatternPainter()),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(56),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(30),
                      shape: BoxShape.circle,
                    ),
                    child: Image.asset('assets/logo.png', height: 80, color: Colors.white),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Mitroo',
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Διαχείριση Οργανισμού',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white70,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 48),
                  _buildFeatureTile(Icons.security_outlined, 'Ασφαλής Πρόσβαση', 'Προστατευμένα δεδομένα μελών'),
                  const SizedBox(height: 16),
                  _buildFeatureTile(Icons.people_outline, 'Διαχείριση Μελών', 'Πλήρης εποπτεία του οργανισμού'),
                  const SizedBox(height: 16),
                  _buildFeatureTile(Icons.school_outlined, 'Εκπαίδευση', 'Παρακολούθηση και αιτήσεις εκπαίδευσης'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureTile(IconData icon, String title, String subtitle) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(25),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
            Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ],
        ),
      ],
    );
  }

  Widget _buildMobileHeader() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _primaryRed,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _primaryRed.withAlpha(80),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Image.asset('assets/logo.png', height: 48, color: Colors.white),
        ),
        const SizedBox(height: 16),
        const Text(
          'Mitroo',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF1A1C1E), letterSpacing: -0.5),
        ),
        const SizedBox(height: 4),
        const Text(
          'Διαχείριση Οργανισμού',
          style: TextStyle(fontSize: 14, color: _subtleGray),
        ),
      ],
    );
  }

  Widget _buildFormContent(AuthProvider auth, {required bool isDesktop}) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _primaryRed.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.lock_person_outlined, color: _primaryRed, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  _isRegister ? 'Δημιουργία Λογαριασμού' : 'Καλώς Ορίσατε',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF1A1C1E)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 48),
              child: Text(
                _isRegister ? 'Δημιουργήστε λογαριασμό για πρόσβαση στο σύστημα' : 'Συνδεθείτε για να συνεχίσετε',
                style: const TextStyle(fontSize: 13, color: _subtleGray),
              ),
            ),
            const SizedBox(height: 32),
          ] else ...[
            Text(
              _isRegister ? 'Δημιουργία Λογαριασμού' : 'Σύνδεση',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF1A1C1E)),
            ),
            const SizedBox(height: 4),
            Text(
              _isRegister ? 'Συμπληρώστε τα στοιχεία σας' : 'Εισάγετε τα στοιχεία σας για πρόσβαση',
              style: const TextStyle(fontSize: 13, color: _subtleGray),
            ),
            const SizedBox(height: 24),
          ],
          if (_error != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade600, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13))),
                ],
              ),
            ),
          ],
          if (_isRegister) ...[
            TextFormField(
              controller: _forenameCtrl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Όνομα', prefixIcon: Icon(Icons.person_outline)),
              validator: (v) => (v == null || v.isEmpty) ? 'Υποχρεωτικό' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _surnameCtrl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Επώνυμο', prefixIcon: Icon(Icons.person_outline)),
              validator: (v) => (v == null || v.isEmpty) ? 'Υποχρεωτικό' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _enameCtrl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Κωδικός Μέλους', prefixIcon: Icon(Icons.badge_outlined)),
              validator: (v) => (v == null || v.length < 2) ? 'Τουλάχιστον 2 χαρακτήρες' : null,
            ),
            const SizedBox(height: 14),
          ],
          TextFormField(
            controller: _emailCtrl,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
            keyboardType: TextInputType.emailAddress,
            validator: (v) => (v == null || !v.contains('@')) ? 'Εισάγετε έγκυρο email' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _passwordCtrl,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => auth.loading ? null : _submit(),
            decoration: InputDecoration(
              labelText: 'Κωδικός',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            validator: (v) => (v == null || v.length < 4) ? 'Τουλάχιστον 4 χαρακτήρες' : null,
          ),
          if (!_isRegister) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => context.go('/forgot-password'),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: const Text('Ξεχάσατε τον κωδικό;', style: TextStyle(fontSize: 12, color: _primaryRed)),
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: auth.loading ? null : _submit,
              child: auth.loading
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Text(
                      _isRegister ? 'Δημιουργία Λογαριασμού' : 'Σύνδεση',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.2),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('ή', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: () => setState(() {
                _isRegister = !_isRegister;
                _error = null;
              }),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFE0E0E0)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                _isRegister ? 'Έχετε ήδη λογαριασμό; Σύνδεση' : 'Δεν έχετε λογαριασμό; Εγγραφή',
                style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
              ),
            ),
          ),
          if (!_isRegister) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () => context.go('/apply-training'),
                icon: const Icon(Icons.school_outlined, size: 18, color: _primaryRed),
                label: const Text(
                  'Αίτηση Εκπαίδευσης — Ελληνικός Ερυθρός Σταυρός',
                  style: TextStyle(fontSize: 12, color: _primaryRed),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _primaryRed),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CirclePatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.15), 120, paint);
    canvas.drawCircle(Offset(size.width * 0.1, size.height * 0.75), 160, paint);
    canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.9), 80, paint);

    final fillPaint = Paint()
      ..color = Colors.white.withAlpha(8)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.15), 80, fillPaint);
    canvas.drawCircle(Offset(size.width * 0.1, size.height * 0.75), 100, fillPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
