import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no hardcoded Color(0xFFxxxxxx) literals outside lib/theme/', () {
    final libDir = Directory('lib');
    final pattern = RegExp(r'Color\(0xFF[0-9A-Fa-f]{6}\)');
    final offenders = <String>[];

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final normalized = entity.path.replaceAll('\\', '/');
      if (normalized.startsWith('lib/theme/')) continue;

      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i])) {
          offenders.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Found hardcoded Color(0xFFxxxxxx) literals outside lib/theme/. '
          'Use a token from lib/theme/app_colors.dart (AppColors) instead:\n'
          '${offenders.join('\n')}',
    );
  });
}
