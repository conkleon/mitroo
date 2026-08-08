import 'package:flutter/material.dart';

import 'package:mitroo_frontend/theme/theme.dart';

class StaleBanner extends StatelessWidget {
  final bool isStale;
  const StaleBanner({super.key, required this.isStale});

  @override
  Widget build(BuildContext context) {
    if (!isStale) return const SizedBox.shrink();
    return Material(
      color: AppColors.amber100,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: const [
            Icon(Icons.history_rounded, size: 16, color: AppColors.amber800),
            SizedBox(width: 8),
            Text(
              'Εμφάνιση αποθηκευμένων δεδομένων',
              style: TextStyle(
                fontSize: AppFontSize.md,
                color: AppColors.amber800,
                fontWeight: AppFontWeight.medium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
