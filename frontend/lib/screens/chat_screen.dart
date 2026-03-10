import 'package:flutter/material.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: cs.primary.withAlpha(20),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.chat_bubble_outline, size: 56, color: cs.primary),
                ),
                const SizedBox(height: 24),
                Text(
                  'Chat',
                  style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Τα μηνύματα ομάδας έρχονται σύντομα.\nΜείνετε συντονισμένοι!',
                  textAlign: TextAlign.center,
                  style: tt.bodyMedium?.copyWith(color: const Color(0xFF6B7280), height: 1.5),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.notifications_outlined, size: 18),
                  label: const Text('Ειδοποίηση όταν είναι έτοιμο'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
