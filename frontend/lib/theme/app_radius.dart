import 'package:flutter/material.dart';

/// Border radius tokens — one per distinct `BorderRadius.circular(N)` value
/// found across the app today. Not `const` because `BorderRadius.circular`
/// is a regular factory, not a const constructor (matches how it was
/// already used at every call site before this migration).
class AppRadius {
  AppRadius._();

  static final BorderRadius r1 = BorderRadius.circular(1);
  static final BorderRadius r2 = BorderRadius.circular(2);
  static final BorderRadius r3 = BorderRadius.circular(3);
  static final BorderRadius r4 = BorderRadius.circular(4);
  static final BorderRadius r6 = BorderRadius.circular(6);
  static final BorderRadius r7 = BorderRadius.circular(7);
  static final BorderRadius r8 = BorderRadius.circular(8);
  static final BorderRadius r10 = BorderRadius.circular(10);
  static final BorderRadius r11 = BorderRadius.circular(11);
  static final BorderRadius r12 = BorderRadius.circular(12);
  static final BorderRadius r14 = BorderRadius.circular(14);
  static final BorderRadius r16 = BorderRadius.circular(16);
  static final BorderRadius r20 = BorderRadius.circular(20);
  static final BorderRadius r24 = BorderRadius.circular(24);
  static final BorderRadius pill = BorderRadius.circular(999);
}
