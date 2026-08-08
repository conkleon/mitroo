import 'package:flutter/material.dart';

/// Font size tokens — one per distinct `fontSize:` literal found across
/// the app today.
class AppFontSize {
  AppFontSize._();

  static const double xxs = 9;
  static const double xs = 10;
  static const double sm = 11;
  static const double base = 12;
  static const double md = 13;
  static const double lg = 14;
  static const double xl = 15;
  static const double xl2 = 16;
  static const double xl3 = 18;
  static const double xl4 = 20;
  static const double xl5 = 22;
  static const double display = 28;
  static const double display2 = 30;
  static const double display3 = 32;
  static const double hero = 52;
}

/// Font weight tokens — one per distinct `FontWeight.wN` used across the app.
class AppFontWeight {
  AppFontWeight._();

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semibold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;
  static const FontWeight extrabold = FontWeight.w800;
}

/// Composed text style presets for the most common size+weight repeats.
/// Opportunistic — screens are not required to adopt these, they can keep
/// using [AppFontSize]/[AppFontWeight] directly for exact per-call control.
class AppTextStyles {
  AppTextStyles._();

  static const TextStyle heading1 =
      TextStyle(fontSize: AppFontSize.display, fontWeight: AppFontWeight.bold);
  static const TextStyle sectionTitle =
      TextStyle(fontSize: AppFontSize.xl5, fontWeight: AppFontWeight.bold);
  static const TextStyle cardTitle =
      TextStyle(fontSize: AppFontSize.xl2, fontWeight: AppFontWeight.bold);
  static const TextStyle subtitle =
      TextStyle(fontSize: AppFontSize.lg, fontWeight: AppFontWeight.semibold);
  static const TextStyle body =
      TextStyle(fontSize: AppFontSize.md, fontWeight: AppFontWeight.regular);
  static const TextStyle bodyStrong =
      TextStyle(fontSize: AppFontSize.md, fontWeight: AppFontWeight.semibold);
  static const TextStyle caption =
      TextStyle(fontSize: AppFontSize.base, fontWeight: AppFontWeight.medium);
  static const TextStyle label =
      TextStyle(fontSize: AppFontSize.sm, fontWeight: AppFontWeight.semibold);
}
