import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/connectivity_provider.dart';
import '../providers/victim_provider.dart';

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

    final color =
        isOnline ? const Color(0xFFFEF3C7) : const Color(0xFFFEE2E2);
    final textColor =
        isOnline ? const Color(0xFF92400E) : const Color(0xFF991B1B);

    return Material(
      color: color,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(
              isOnline
                  ? Icons.cloud_upload_outlined
                  : Icons.wifi_off_rounded,
              size: 16,
              color: textColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 13,
                  color: textColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (pending > 0)
              TextButton(
                onPressed:
                    isOnline ? () => victims.syncOutbox() : null,
                style: TextButton.styleFrom(foregroundColor: textColor),
                child: const Text('Συγχρονισμός'),
              ),
          ],
        ),
      ),
    );
  }
}
