import 'package:flutter/material.dart';

/// Design-system color tokens. Named after their Tailwind CSS shade where
/// the value matches Tailwind's default palette exactly; a handful of
/// custom brand/near-gray values are named descriptively instead.
class AppColors {
  AppColors._();

  // Brand
  static const Color brandPrimary = Color(0xFFC62828);
  static const Color brandAccent = Color(0xFFE53935);
  static const Color brandDark = Color(0xFF6B0000);

  // Gray
  static const Color gray50 = Color(0xFFF9FAFB);
  static const Color gray100 = Color(0xFFF3F4F6);
  static const Color gray200 = Color(0xFFE5E7EB);
  static const Color gray300 = Color(0xFFD1D5DB);
  static const Color gray400 = Color(0xFF9CA3AF);
  static const Color gray500 = Color(0xFF6B7280);
  static const Color gray600 = Color(0xFF4B5563);
  static const Color gray700 = Color(0xFF374151);
  static const Color gray800 = Color(0xFF1F2937);
  static const Color gray900 = Color(0xFF111827);

  // Neutral extras (custom near-gray values, kept exact — do not collapse
  // into the gray scale above, they are not the same value).
  static const Color ink = Color(0xFF1A1C1E);
  static const Color borderSubtle = Color(0xFFE0E0E0);
  static const Color divider = Color(0xFFE8ECF0);
  static const Color surfaceTint = Color(0xFFEEF0F4);
  static const Color surfaceTint2 = Color(0xFFE9EBF0);
  static const Color slate50 = Color(0xFFF8FAFC);
  static const Color surfaceAlt = Color(0xFFF5F7FA);

  // Red
  static const Color red50 = Color(0xFFFEF2F2);
  static const Color red100 = Color(0xFFFEE2E2);
  static const Color red200 = Color(0xFFFECACA);
  static const Color red300 = Color(0xFFFCA5A5);
  static const Color red400 = Color(0xFFF87171);
  static const Color red500 = Color(0xFFEF4444);
  static const Color red600 = Color(0xFFDC2626);
  static const Color red700 = Color(0xFFB91C1C);
  static const Color red800 = Color(0xFF991B1B);

  // Orange
  static const Color orange50 = Color(0xFFFFF7ED);
  static const Color orange300 = Color(0xFFFED7AA);
  static const Color orange600 = Color(0xFFEA580C);
  static const Color orange700 = Color(0xFFC2410C);
  static const Color orange800 = Color(0xFF9A3412);
  static const Color orangeDeep = Color(0xFFD84315);

  // Amber
  static const Color amber50 = Color(0xFFFFFBEB);
  static const Color amber100 = Color(0xFFFEF3C7);
  static const Color amber300 = Color(0xFFFDE68A);
  static const Color amber500 = Color(0xFFF59E0B);
  static const Color amber600 = Color(0xFFD97706);
  static const Color amber700 = Color(0xFFB45309);
  static const Color amber800 = Color(0xFF92400E);

  // Green / Emerald
  static const Color green50 = Color(0xFFF0FDF4);
  static const Color green200 = Color(0xFFBBF7D0);
  static const Color emerald100 = Color(0xFFD1FAE5);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald600 = Color(0xFF059669);

  // Teal
  static const Color teal600 = Color(0xFF0D9488);
  static const Color teal700 = Color(0xFF0F766E);

  // Cyan / Sky
  static const Color cyan50 = Color(0xFFECFEFF);
  static const Color cyan600 = Color(0xFF0891B2);
  static const Color sky500 = Color(0xFF0EA5E9);

  // Blue / Indigo
  static const Color indigo50 = Color(0xFFEEF2FF);
  static const Color blue100 = Color(0xFFDBEAFE);
  static const Color blue500 = Color(0xFF3B82F6);
  static const Color blue600 = Color(0xFF2563EB);
  static const Color blue700 = Color(0xFF1D4ED8);
  static const Color blueDeep = Color(0xFF0D47A1);
  static const Color indigo500 = Color(0xFF6366F1);
  static const Color indigo950 = Color(0xFF1E1B4B);

  // Violet / Purple
  static const Color violet50 = Color(0xFFF5F3FF);
  static const Color violet100 = Color(0xFFEDE9FE);
  static const Color violet200 = Color(0xFFDDD6FE);
  static const Color violet500 = Color(0xFF8B5CF6);
  static const Color violet600 = Color(0xFF7C3AED);
  static const Color violet700 = Color(0xFF6D28D9);
  static const Color violet800 = Color(0xFF5B21B6);

  // Semantic aliases (point at the tokens above; use where the meaning is
  // consistent, e.g. status chips / role badges).
  static const Color success = emerald600;
  static const Color successBg = emerald100;
  static const Color danger = red600;
  static const Color dangerBg = red100;
  static const Color warning = amber600;
  static const Color warningBg = amber100;
  static const Color info = cyan600;
  static const Color infoBg = cyan50;
  static const Color accent = violet600;
  static const Color accentBg = violet100;
  static const Color textPrimary = ink;
  static const Color textSecondary = gray500;
  static const Color textTertiary = gray400;
  static const Color border = gray200;
}
