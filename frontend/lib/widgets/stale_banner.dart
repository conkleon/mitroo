import 'package:flutter/material.dart';

class StaleBanner extends StatelessWidget {
  final bool isStale;
  const StaleBanner({super.key, required this.isStale});

  @override
  Widget build(BuildContext context) {
    if (!isStale) return const SizedBox.shrink();
    return Material(
      color: const Color(0xFFFEF3C7),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: const [
            Icon(Icons.history_rounded, size: 16, color: Color(0xFF92400E)),
            SizedBox(width: 8),
            Text(
              'Εμφάνιση αποθηκευμένων δεδομένων',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF92400E),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
