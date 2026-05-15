import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;
import '../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  String? _error;
  bool _isRegister = false;
  bool _obscurePassword = true;
  final _forenameCtrl = TextEditingController();
  final _surnameCtrl = TextEditingController();
  final _enameCtrl = TextEditingController();

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _forenameCtrl.dispose();
    _surnameCtrl.dispose();
    _enameCtrl.dispose();
    _fadeCtrl.dispose();
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

  void _toggleMode() {
    setState(() {
      _isRegister = !_isRegister;
      _error = null;
    });
    _fadeCtrl.forward(from: 0.4);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;

    return Scaffold(
      backgroundColor: Colors.white,
      body: isWide
          ? Row(children: [
              Expanded(flex: 5, child: _BrandPanel()),
              Expanded(flex: 4, child: _buildFormPanel(auth)),
            ])
          : Column(children: [
              _CompactBrandHeader(),
              Expanded(child: _buildFormPanel(auth)),
            ]),
    );
  }

  Widget _buildFormPanel(AuthProvider auth) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Container(
        color: Colors.white,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FormHeader(isRegister: _isRegister),
                    const SizedBox(height: 32),
                    if (_error != null) ...[
                      _ErrorBanner(message: _error!),
                      const SizedBox(height: 20),
                    ],
                    if (_isRegister) ...[
                      Row(
                        children: [
                          Expanded(
                            child: _FormField(
                              controller: _forenameCtrl,
                              label: 'Όνομα',
                              icon: Icons.person_outline_rounded,
                              validator: (v) =>
                                  (v == null || v.isEmpty) ? 'Υποχρεωτικό' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _FormField(
                              controller: _surnameCtrl,
                              label: 'Επώνυμο',
                              icon: Icons.person_outline_rounded,
                              validator: (v) =>
                                  (v == null || v.isEmpty) ? 'Υποχρεωτικό' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _FormField(
                        controller: _enameCtrl,
                        label: 'Κωδικός Μέλους',
                        icon: Icons.badge_outlined,
                        validator: (v) => (v == null || v.length < 2)
                            ? 'Τουλάχιστον 2 χαρακτήρες'
                            : null,
                      ),
                      const SizedBox(height: 14),
                    ],
                    _FormField(
                      controller: _emailCtrl,
                      label: 'Email',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => (v == null || !v.contains('@'))
                          ? 'Εισάγετε έγκυρο email'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: _obscurePassword,
                      style: const TextStyle(
                          fontSize: 14, color: Color(0xFF1A1C1E)),
                      decoration: InputDecoration(
                        labelText: 'Κωδικός',
                        prefixIcon: const Icon(Icons.lock_outline_rounded,
                            size: 20, color: Color(0xFF9CA3AF)),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 20,
                            color: const Color(0xFF9CA3AF),
                          ),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (v) => (v == null || v.length < 4)
                          ? 'Τουλάχιστον 4 χαρακτήρες'
                          : null,
                    ),
                    if (!_isRegister) ...[
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => context.go('/forgot-password'),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            minimumSize: const Size(0, 28),
                          ),
                          child: const Text('Ξεχάσατε τον κωδικό;',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    _SubmitButton(
                        loading: auth.loading,
                        isRegister: _isRegister,
                        onPressed: _submit),
                    const SizedBox(height: 14),
                    Center(
                      child: TextButton(
                        onPressed: _toggleMode,
                        child: Text(
                          _isRegister
                              ? 'Έχετε ήδη λογαριασμό; Σύνδεση'
                              : 'Δεν έχετε λογαριασμό; Εγγραφή',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                    if (!_isRegister) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text('ή',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade400)),
                        ),
                        const Expanded(child: Divider()),
                      ]),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => context.go('/apply-training'),
                          icon: const Icon(Icons.school_outlined, size: 18),
                          label: const Text(
                            'Αίτηση Εκπαίδευσης — Ε.Ε.Σ.',
                            style: TextStyle(fontSize: 13),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Brand panel (wide layout) ─────────────────────────────────────────────────

class _BrandPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6B0000), Color(0xFFC62828), Color(0xFFD84315)],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _CrossGridPainter())),
          // Diagonal accent stripe
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 4,
            child: Container(color: Colors.white.withAlpha(30)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 48, 40, 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top identifier
                Row(
                  children: [
                    Image.asset('assets/logo.png', height: 56),
                    const SizedBox(width: 12),
                    Text(
                      'R.C.D.',
                      style: GoogleFonts.spaceGrotesk(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3,
                      ),
                    ),
                  ],
                ),
                const Spacer(flex: 2),
                // Status tag
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(25),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: Colors.white.withAlpha(50), width: 1),
                  ),
                  child: Text(
                    'ΕΛΛΗΝΙΚΟΣ ΕΡΥΘΡΟΣ ΣΤΑΥΡΟΣ',
                    style: GoogleFonts.spaceGrotesk(
                      color: Colors.white.withAlpha(200),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2.5,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Main headline
                Text(
                  'Red Cross\nDispatcher',
                  style: GoogleFonts.playfairDisplay(
                    color: Colors.white,
                    fontSize: 52,
                    fontWeight: FontWeight.w700,
                    height: 1.05,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: 40,
                  height: 2,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(180),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Σύστημα διαχείρισης πόρων\nκαι αποστολών έκτακτης ανάγκης.',
                  style: GoogleFonts.spaceGrotesk(
                    color: Colors.white.withAlpha(190),
                    fontSize: 15,
                    height: 1.65,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const Spacer(flex: 3),
                // Capability chips
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: const [
                    _CapChip(icon: Icons.people_outline_rounded, label: 'Εθελοντές'),
                    _CapChip(icon: Icons.inventory_2_outlined, label: 'Εξοπλισμός'),
                    _CapChip(icon: Icons.local_shipping_outlined, label: 'Οχήματα'),
                    _CapChip(icon: Icons.assignment_outlined, label: 'Αποστολές'),
                  ],
                ),
                const SizedBox(height: 32),
                // Version tag
                Text(
                  'v2.0 · Secure Access',
                  style: TextStyle(
                    color: Colors.white.withAlpha(100),
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactBrandHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 52, 24, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6B0000), Color(0xFFC62828)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Image.asset('assets/logo.png', height: 36),
            const SizedBox(width: 8),
            Text(
              'R.C.D.',
              style: GoogleFonts.spaceGrotesk(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.5,
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            'Red Cross Dispatcher',
            style: GoogleFonts.playfairDisplay(
              color: Colors.white.withAlpha(220),
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Form sub-widgets ──────────────────────────────────────────────────────────

class _FormHeader extends StatelessWidget {
  final bool isRegister;
  const _FormHeader({required this.isRegister});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        isRegister ? 'Νέος Λογαριασμός' : 'Καλώς ήρθατε',
        style: GoogleFonts.playfairDisplay(
          fontSize: 30,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF1A1C1E),
          letterSpacing: -0.5,
          height: 1.1,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        isRegister
            ? 'Συμπληρώστε τα στοιχεία σας για εγγραφή'
            : 'Συνδεθείτε με τα διαπιστευτήριά σας',
        style: GoogleFonts.spaceGrotesk(
          fontSize: 13,
          color: const Color(0xFF6B7280),
          fontWeight: FontWeight.w400,
          height: 1.5,
        ),
      ),
    ]);
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 16, color: Color(0xFFDC2626)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  color: Color(0xFFDC2626),
                  fontSize: 13,
                  height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _FormField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(fontSize: 14, color: Color(0xFF1A1C1E)),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: const Color(0xFF9CA3AF)),
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  final bool loading;
  final bool isRegister;
  final VoidCallback onPressed;

  const _SubmitButton({
    required this.loading,
    required this.isRegister,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Text(
                isRegister ? 'Δημιουργία Λογαριασμού' : 'Σύνδεση',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
      ),
    );
  }
}

class _CapChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _CapChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withAlpha(45), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white.withAlpha(200), size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withAlpha(200),
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Painters ──────────────────────────────────────────────────────────────────

class _CrossGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(14)
      ..style = PaintingStyle.fill;

    void drawCross(double cx, double cy, double s, double angle) {
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(angle);
      final arm = s * 0.28;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: s, height: arm),
          const Radius.circular(3),
        ),
        paint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: arm, height: s),
          const Radius.circular(3),
        ),
        paint,
      );
      canvas.restore();
    }

    drawCross(size.width * 0.78, size.height * 0.12, 90, 0);
    drawCross(size.width * 0.12, size.height * 0.22, 50, math.pi / 12);
    drawCross(size.width * 0.65, size.height * 0.72, 130, math.pi / 8);
    drawCross(size.width * 0.35, size.height * 0.88, 60, 0);
    drawCross(size.width * 0.88, size.height * 0.52, 45, math.pi / 6);
    drawCross(size.width * 0.20, size.height * 0.58, 70, -math.pi / 10);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
