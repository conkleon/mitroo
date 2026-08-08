import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/connectivity_provider.dart';
import '../providers/victim_provider.dart';

import 'package:mitroo_frontend/theme/theme.dart';

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final isOnline = context.watch<ConnectivityProvider>().isOnline;
    final victims = context.watch<VictimProvider>();
    final pending = victims.pendingCount;

    if (isOnline && pending == 0) return const SizedBox.shrink();

    final String message;
    if (!isOnline && pending == 0) {
      message = 'Χωρίς σύνδεση';
    } else if (!isOnline) {
      message = 'Χωρίς σύνδεση — $pending αναφορές εκκρεμούν';
    } else {
      message = '$pending αναφορές εκκρεμούν';
    }

    final color = isOnline ? AppColors.amber100 : AppColors.red100;
    final textColor = isOnline ? AppColors.amber800 : AppColors.red800;

    return Material(
      color: color,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(
              isOnline ? Icons.cloud_upload_outlined : Icons.wifi_off_rounded,
              size: 16,
              color: textColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: AppFontSize.md,
                  color: textColor,
                  fontWeight: AppFontWeight.medium,
                ),
              ),
            ),
            if (pending > 0)
              TextButton(
                onPressed: isOnline ? () => victims.syncOutbox() : null,
                style: TextButton.styleFrom(foregroundColor: textColor),
                child: const Text('Συγχρονισμός'),
              ),
          ],
        ),
      ),
    );
  }
}
