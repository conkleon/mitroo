import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mitroo_frontend/theme/theme.dart';

void main() {
  group('AppColors', () {
    test('brand colors match original main.dart constants', () {
      expect(AppColors.brandPrimary, const Color(0xFFC62828));
      expect(AppColors.brandAccent, const Color(0xFFE53935));
      expect(AppColors.brandDark, const Color(0xFF6B0000));
    });

    test('gray scale matches Tailwind gray values', () {
      expect(AppColors.gray50, const Color(0xFFF9FAFB));
      expect(AppColors.gray100, const Color(0xFFF3F4F6));
      expect(AppColors.gray200, const Color(0xFFE5E7EB));
      expect(AppColors.gray300, const Color(0xFFD1D5DB));
      expect(AppColors.gray400, const Color(0xFF9CA3AF));
      expect(AppColors.gray500, const Color(0xFF6B7280));
      expect(AppColors.gray600, const Color(0xFF4B5563));
      expect(AppColors.gray700, const Color(0xFF374151));
      expect(AppColors.gray800, const Color(0xFF1F2937));
      expect(AppColors.gray900, const Color(0xFF111827));
    });

    test('neutral extras match custom near-gray values', () {
      expect(AppColors.ink, const Color(0xFF1A1C1E));
      expect(AppColors.borderSubtle, const Color(0xFFE0E0E0));
      expect(AppColors.divider, const Color(0xFFE8ECF0));
      expect(AppColors.surfaceTint, const Color(0xFFEEF0F4));
      expect(AppColors.surfaceTint2, const Color(0xFFE9EBF0));
      expect(AppColors.slate50, const Color(0xFFF8FAFC));
      expect(AppColors.surfaceAlt, const Color(0xFFF5F7FA));
    });

    test('red scale matches Tailwind red values', () {
      expect(AppColors.red50, const Color(0xFFFEF2F2));
      expect(AppColors.red100, const Color(0xFFFEE2E2));
      expect(AppColors.red200, const Color(0xFFFECACA));
      expect(AppColors.red300, const Color(0xFFFCA5A5));
      expect(AppColors.red400, const Color(0xFFF87171));
      expect(AppColors.red500, const Color(0xFFEF4444));
      expect(AppColors.red600, const Color(0xFFDC2626));
      expect(AppColors.red700, const Color(0xFFB91C1C));
      expect(AppColors.red800, const Color(0xFF991B1B));
    });

    test('orange scale matches expected values', () {
      expect(AppColors.orange50, const Color(0xFFFFF7ED));
      expect(AppColors.orange300, const Color(0xFFFED7AA));
      expect(AppColors.orange600, const Color(0xFFEA580C));
      expect(AppColors.orange700, const Color(0xFFC2410C));
      expect(AppColors.orange800, const Color(0xFF9A3412));
      expect(AppColors.orangeDeep, const Color(0xFFD84315));
    });

    test('amber scale matches Tailwind amber values', () {
      expect(AppColors.amber50, const Color(0xFFFFFBEB));
      expect(AppColors.amber100, const Color(0xFFFEF3C7));
      expect(AppColors.amber300, const Color(0xFFFDE68A));
      expect(AppColors.amber500, const Color(0xFFF59E0B));
      expect(AppColors.amber600, const Color(0xFFD97706));
      expect(AppColors.amber700, const Color(0xFFB45309));
      expect(AppColors.amber800, const Color(0xFF92400E));
    });

    test('green/emerald scale matches expected values', () {
      expect(AppColors.green50, const Color(0xFFF0FDF4));
      expect(AppColors.green200, const Color(0xFFBBF7D0));
      expect(AppColors.emerald100, const Color(0xFFD1FAE5));
      expect(AppColors.emerald500, const Color(0xFF10B981));
      expect(AppColors.emerald600, const Color(0xFF059669));
    });

    test('teal, cyan, sky match expected values', () {
      expect(AppColors.teal600, const Color(0xFF0D9488));
      expect(AppColors.teal700, const Color(0xFF0F766E));
      expect(AppColors.cyan50, const Color(0xFFECFEFF));
      expect(AppColors.cyan600, const Color(0xFF0891B2));
      expect(AppColors.sky500, const Color(0xFF0EA5E9));
    });

    test('blue/indigo scale matches expected values', () {
      expect(AppColors.indigo50, const Color(0xFFEEF2FF));
      expect(AppColors.blue100, const Color(0xFFDBEAFE));
      expect(AppColors.blue500, const Color(0xFF3B82F6));
      expect(AppColors.blue600, const Color(0xFF2563EB));
      expect(AppColors.blue700, const Color(0xFF1D4ED8));
      expect(AppColors.blueDeep, const Color(0xFF0D47A1));
      expect(AppColors.indigo500, const Color(0xFF6366F1));
      expect(AppColors.indigo950, const Color(0xFF1E1B4B));
    });

    test('violet scale matches expected values', () {
      expect(AppColors.violet50, const Color(0xFFF5F3FF));
      expect(AppColors.violet100, const Color(0xFFEDE9FE));
      expect(AppColors.violet200, const Color(0xFFDDD6FE));
      expect(AppColors.violet500, const Color(0xFF8B5CF6));
      expect(AppColors.violet600, const Color(0xFF7C3AED));
      expect(AppColors.violet700, const Color(0xFF6D28D9));
      expect(AppColors.violet800, const Color(0xFF5B21B6));
    });

    test('semantic aliases point at the correct palette tokens', () {
      expect(AppColors.success, AppColors.emerald600);
      expect(AppColors.successBg, AppColors.emerald100);
      expect(AppColors.danger, AppColors.red600);
      expect(AppColors.dangerBg, AppColors.red100);
      expect(AppColors.warning, AppColors.amber600);
      expect(AppColors.warningBg, AppColors.amber100);
      expect(AppColors.info, AppColors.cyan600);
      expect(AppColors.infoBg, AppColors.cyan50);
      expect(AppColors.accent, AppColors.violet600);
      expect(AppColors.accentBg, AppColors.violet100);
      expect(AppColors.textPrimary, AppColors.ink);
      expect(AppColors.textSecondary, AppColors.gray500);
      expect(AppColors.textTertiary, AppColors.gray400);
      expect(AppColors.border, AppColors.gray200);
    });
  });
}
