import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Result returned by the scanner screen via Navigator.pop().
class ScanResult {
  /// The raw string value from the scanned code.
  final String value;

  /// Whether this came from a QR code (true) or a 1-D barcode (false).
  final bool isQr;

  const ScanResult({required this.value, required this.isQr});
}

/// Full-screen camera scanner that detects both QR codes and barcodes.
/// Returns a [ScanResult] via `Navigator.pop` when a code is detected.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  late final MobileScannerController _controller;
  bool _hasPopped = false;
  bool _torchOn = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasPopped) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final barcode = barcodes.first;
    final rawValue = barcode.rawValue;
    if (rawValue == null || rawValue.isEmpty) return;

    // QR codes use BarcodeFormat.qrCode; everything else is a 1-D barcode.
    final isQr = barcode.format == BarcodeFormat.qrCode;

    _hasPopped = true;
    Navigator.of(context).pop(ScanResult(value: rawValue, isQr: isQr));
  }

  void _toggleTorch() {
    _controller.toggleTorch();
    setState(() => _torchOn = !_torchOn);
  }

  void _switchCamera() {
    _controller.switchCamera();
  }

  void _showManualEntry() {
    bool isQr = true;
    String selectedValue = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          return AlertDialog(
            title: const Text('Enter Code'),
            content: SizedBox(
              width: 350,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('QR / ID'), icon: Icon(Icons.qr_code)),
                      ButtonSegment(value: false, label: Text('Barcode'), icon: Icon(Icons.barcode_reader)),
                    ],
                    selected: {isQr},
                    onSelectionChanged: (v) => setSt(() => isQr = v.first),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: isQr ? 'Item ID' : 'Barcode value',
                      hintText: isQr ? 'e.g. 42' : 'e.g. ABC-123',
                      prefixIcon: Icon(isQr ? Icons.tag : Icons.barcode_reader),
                    ),
                    keyboardType: isQr ? TextInputType.number : TextInputType.text,
                    onChanged: (v) => selectedValue = v,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  final value = selectedValue.trim();
                  if (value.isEmpty) return;
                  Navigator.pop(ctx); // close dialog
                  if (_hasPopped) return;
                  _hasPopped = true;
                  Navigator.of(context).pop(ScanResult(value: value, isQr: isQr));
                },
                child: const Text('Look up'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Camera preview ──
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videocam_off, color: Colors.white54, size: 64),
                      const SizedBox(height: 16),
                      Text(
                        'Camera unavailable',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        error.errorDetails?.message ?? 'Could not access the camera. Please check permissions.',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        icon: const Icon(Icons.keyboard_outlined),
                        label: const Text('Enter code manually'),
                        onPressed: _showManualEntry,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // ── Scan overlay ──
          _ScanOverlay(),

          // ── Top bar ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    Text(
                      'Scan QR or Barcode',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48), // balance the back button
                  ],
                ),
              ),
            ),
          ),

          // ── Bottom controls ──
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Point the camera at a QR code or barcode',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _controlButton(
                          icon: _torchOn ? Icons.flash_on : Icons.flash_off,
                          label: 'Flash',
                          onTap: _toggleTorch,
                          active: _torchOn,
                          cs: cs,
                        ),
                        _controlButton(
                          icon: Icons.keyboard_outlined,
                          label: 'Type',
                          onTap: _showManualEntry,
                          cs: cs,
                        ),
                        _controlButton(
                          icon: Icons.cameraswitch_outlined,
                          label: 'Flip',
                          onTap: _switchCamera,
                          cs: cs,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
    required ColorScheme cs,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: active ? cs.primary : Colors.white.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}

/// Draws a rounded-rect viewfinder overlay on top of the camera preview.
class _ScanOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final scanArea = size.width * 0.7;
        final left = (size.width - scanArea) / 2;
        final top = (size.height - scanArea) / 2 - 40;

        return Stack(
          children: [
            // Semi-transparent background
            ColorFiltered(
              colorFilter: const ColorFilter.mode(Colors.black54, BlendMode.srcOut),
              child: Stack(
                children: [
                  Container(decoration: const BoxDecoration(color: Colors.black, backgroundBlendMode: BlendMode.dstOut)),
                  Positioned(
                    left: left,
                    top: top,
                    child: Container(
                      width: scanArea,
                      height: scanArea,
                      decoration: BoxDecoration(
                        color: Colors.red, // any opaque color for cutout
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Corner brackets
            Positioned(
              left: left,
              top: top,
              child: _CornerBrackets(size: scanArea),
            ),
          ],
        );
      },
    );
  }
}

/// Draws four corner brackets around the scan area.
class _CornerBrackets extends StatelessWidget {
  final double size;
  const _CornerBrackets({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _BracketPainter()),
    );
  }
}

class _BracketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const len = 30.0;
    const r = 16.0;

    // Top-left
    canvas.drawPath(
      Path()
        ..moveTo(0, len)
        ..lineTo(0, r)
        ..quadraticBezierTo(0, 0, r, 0)
        ..lineTo(len, 0),
      paint,
    );
    // Top-right
    canvas.drawPath(
      Path()
        ..moveTo(size.width - len, 0)
        ..lineTo(size.width - r, 0)
        ..quadraticBezierTo(size.width, 0, size.width, r)
        ..lineTo(size.width, len),
      paint,
    );
    // Bottom-left
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height - len)
        ..lineTo(0, size.height - r)
        ..quadraticBezierTo(0, size.height, r, size.height)
        ..lineTo(len, size.height),
      paint,
    );
    // Bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(size.width - len, size.height)
        ..lineTo(size.width - r, size.height)
        ..quadraticBezierTo(size.width, size.height, size.width, size.height - r)
        ..lineTo(size.width, size.height - len),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
