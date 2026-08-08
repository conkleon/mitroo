import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mitroo_frontend/theme/theme.dart';

void main() {
  group('AppFontSize', () {
    test('matches every distinct fontSize literal found in the codebase', () {
      expect(AppFontSize.xxs, 9);
      expect(AppFontSize.xs, 10);
      expect(AppFontSize.sm, 11);
      expect(AppFontSize.base, 12);
      expect(AppFontSize.md, 13);
      expect(AppFontSize.lg, 14);
      expect(AppFontSize.xl, 15);
      expect(AppFontSize.xl2, 16);
      expect(AppFontSize.xl3, 18);
      expect(AppFontSize.xl4, 20);
      expect(AppFontSize.xl5, 22);
      expect(AppFontSize.display, 28);
      expect(AppFontSize.display2, 30);
      expect(AppFontSize.display3, 32);
      expect(AppFontSize.hero, 52);
    });
  });

  group('AppFontWeight', () {
    test('matches every FontWeight used in the codebase', () {
      expect(AppFontWeight.regular, FontWeight.w400);
      expect(AppFontWeight.medium, FontWeight.w500);
      expect(AppFontWeight.semibold, FontWeight.w600);
      expect(AppFontWeight.bold, FontWeight.w700);
      expect(AppFontWeight.extrabold, FontWeight.w800);
    });
  });

  group('AppTextStyles', () {
    test('presets compose the expected size and weight', () {
      expect(AppTextStyles.heading1.fontSize, AppFontSize.display);
      expect(AppTextStyles.heading1.fontWeight, AppFontWeight.bold);
      expect(AppTextStyles.sectionTitle.fontSize, AppFontSize.xl5);
      expect(AppTextStyles.sectionTitle.fontWeight, AppFontWeight.bold);
      expect(AppTextStyles.cardTitle.fontSize, AppFontSize.xl2);
      expect(AppTextStyles.cardTitle.fontWeight, AppFontWeight.bold);
      expect(AppTextStyles.subtitle.fontSize, AppFontSize.lg);
      expect(AppTextStyles.subtitle.fontWeight, AppFontWeight.semibold);
      expect(AppTextStyles.body.fontSize, AppFontSize.md);
      expect(AppTextStyles.body.fontWeight, AppFontWeight.regular);
      expect(AppTextStyles.bodyStrong.fontSize, AppFontSize.md);
      expect(AppTextStyles.bodyStrong.fontWeight, AppFontWeight.semibold);
      expect(AppTextStyles.caption.fontSize, AppFontSize.base);
      expect(AppTextStyles.caption.fontWeight, AppFontWeight.medium);
      expect(AppTextStyles.label.fontSize, AppFontSize.sm);
      expect(AppTextStyles.label.fontWeight, AppFontWeight.semibold);
    });
  });
}
