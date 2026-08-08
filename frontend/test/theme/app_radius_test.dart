import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mitroo_frontend/theme/theme.dart';

void main() {
  group('AppRadius', () {
    test('matches every distinct BorderRadius.circular(N) found in the codebase', () {
      expect(AppRadius.r1, BorderRadius.circular(1));
      expect(AppRadius.r2, BorderRadius.circular(2));
      expect(AppRadius.r3, BorderRadius.circular(3));
      expect(AppRadius.r4, BorderRadius.circular(4));
      expect(AppRadius.r6, BorderRadius.circular(6));
      expect(AppRadius.r7, BorderRadius.circular(7));
      expect(AppRadius.r8, BorderRadius.circular(8));
      expect(AppRadius.r10, BorderRadius.circular(10));
      expect(AppRadius.r11, BorderRadius.circular(11));
      expect(AppRadius.r12, BorderRadius.circular(12));
      expect(AppRadius.r14, BorderRadius.circular(14));
      expect(AppRadius.r16, BorderRadius.circular(16));
      expect(AppRadius.r20, BorderRadius.circular(20));
      expect(AppRadius.r24, BorderRadius.circular(24));
      expect(AppRadius.pill, BorderRadius.circular(999));
    });
  });
}
