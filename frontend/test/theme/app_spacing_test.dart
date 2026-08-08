import 'package:flutter_test/flutter_test.dart';
import 'package:mitroo_frontend/theme/theme.dart';

void main() {
  group('AppSpacing', () {
    test('exposes the standard 4/8/12/16/20/24/32/40 scale', () {
      expect(AppSpacing.xs, 4);
      expect(AppSpacing.sm, 8);
      expect(AppSpacing.md, 12);
      expect(AppSpacing.lg, 16);
      expect(AppSpacing.xl, 20);
      expect(AppSpacing.xl2, 24);
      expect(AppSpacing.xl3, 32);
      expect(AppSpacing.xl4, 40);
    });
  });
}
