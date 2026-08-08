#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const LIB_DIR = path.join(__dirname, '..', 'lib');
const EXCLUDE_DIRS = new Set([path.join(LIB_DIR, 'theme')]);
const EXCLUDE_FILES = new Set([path.join(LIB_DIR, 'main.dart')]);
const DRY_RUN = process.argv.includes('--dry-run');

const COLOR_MAP = {
  // Brand
  C62828: 'brandPrimary', E53935: 'brandAccent', '6B0000': 'brandDark',
  // Gray
  F9FAFB: 'gray50', F3F4F6: 'gray100', E5E7EB: 'gray200', D1D5DB: 'gray300',
  '9CA3AF': 'gray400', '6B7280': 'gray500', '4B5563': 'gray600', '374151': 'gray700',
  '1F2937': 'gray800', '111827': 'gray900',
  // Neutral extras
  '1A1C1E': 'ink', E0E0E0: 'borderSubtle', E8ECF0: 'divider', EEF0F4: 'surfaceTint',
  E9EBF0: 'surfaceTint2', F8FAFC: 'slate50', F5F7FA: 'surfaceAlt',
  // Red
  FEF2F2: 'red50', FEE2E2: 'red100', FECACA: 'red200', FCA5A5: 'red300',
  F87171: 'red400', EF4444: 'red500', DC2626: 'red600', B91C1C: 'red700', '991B1B': 'red800',
  // Orange
  FFF7ED: 'orange50', FED7AA: 'orange300', EA580C: 'orange600', C2410C: 'orange700',
  '9A3412': 'orange800', D84315: 'orangeDeep',
  // Amber
  FFFBEB: 'amber50', FEF3C7: 'amber100', FDE68A: 'amber300', F59E0B: 'amber500',
  D97706: 'amber600', B45309: 'amber700', '92400E': 'amber800',
  // Green / Emerald
  F0FDF4: 'green50', BBF7D0: 'green200', D1FAE5: 'emerald100', '10B981': 'emerald500',
  '059669': 'emerald600',
  // Teal
  '0D9488': 'teal600', '0F766E': 'teal700',
  // Cyan / Sky
  ECFEFF: 'cyan50', '0891B2': 'cyan600', '0EA5E9': 'sky500',
  // Blue / Indigo
  EEF2FF: 'indigo50', DBEAFE: 'blue100', '3B82F6': 'blue500', '2563EB': 'blue600',
  '1D4ED8': 'blue700', '0D47A1': 'blueDeep', '6366F1': 'indigo500', '1E1B4B': 'indigo950',
  // Violet
  F5F3FF: 'violet50', EDE9FE: 'violet100', DDD6FE: 'violet200', '8B5CF6': 'violet500',
  '7C3AED': 'violet600', '6D28D9': 'violet700', '5B21B6': 'violet800',
};

const WEIGHT_MAP = {
  400: 'regular', 500: 'medium', 600: 'semibold', 700: 'bold', 800: 'extrabold',
};

const SIZE_MAP = {
  9: 'xxs', 10: 'xs', 11: 'sm', 12: 'base', 13: 'md', 14: 'lg', 15: 'xl',
  16: 'xl2', 18: 'xl3', 20: 'xl4', 22: 'xl5', 28: 'display', 30: 'display2',
  32: 'display3', 52: 'hero',
};

const RADIUS_MAP = {
  1: 'r1', 2: 'r2', 3: 'r3', 4: 'r4', 6: 'r6', 7: 'r7', 8: 'r8', 10: 'r10',
  11: 'r11', 12: 'r12', 14: 'r14', 16: 'r16', 20: 'r20', 24: 'r24', 999: 'pill',
};

const IMPORT_LINE = "import 'package:mitroo_frontend/theme/theme.dart';";

function walk(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (EXCLUDE_DIRS.has(full) || EXCLUDE_FILES.has(full)) continue;
    if (entry.isDirectory()) walk(full, out);
    else if (entry.name.endsWith('.dart')) out.push(full);
  }
  return out;
}

function migrateFile(filePath, stats) {
  let src = fs.readFileSync(filePath, 'utf8');
  let changed = false;

  src = src.replace(/(const\s+)?Color\(0x(FF[0-9A-Fa-f]{6})\)/g, (match, _const, hexWithFF) => {
    const hex = hexWithFF.slice(2).toUpperCase();
    const token = COLOR_MAP[hex];
    if (!token) {
      stats.unmapped.add(`${path.relative(LIB_DIR, filePath)}: 0x${hexWithFF}`);
      return match;
    }
    changed = true;
    stats.colors++;
    return `AppColors.${token}`;
  });

  src = src.replace(/FontWeight\.w(\d{3})/g, (match, digits) => {
    const token = WEIGHT_MAP[Number(digits)];
    if (!token) {
      stats.unmapped.add(`${path.relative(LIB_DIR, filePath)}: FontWeight.w${digits}`);
      return match;
    }
    changed = true;
    stats.weights++;
    return `AppFontWeight.${token}`;
  });

  src = src.replace(/\bfontSize:\s*(\d+)\b(?!\.\d)/g, (match, digits) => {
    const token = SIZE_MAP[Number(digits)];
    if (!token) {
      stats.unmapped.add(`${path.relative(LIB_DIR, filePath)}: fontSize: ${digits}`);
      return match;
    }
    changed = true;
    stats.sizes++;
    return `fontSize: AppFontSize.${token}`;
  });

  src = src.replace(/BorderRadius\.circular\((\d+)\)/g, (match, digits) => {
    const token = RADIUS_MAP[Number(digits)];
    if (!token) {
      stats.unmapped.add(`${path.relative(LIB_DIR, filePath)}: BorderRadius.circular(${digits})`);
      return match;
    }
    changed = true;
    stats.radii++;
    return `AppRadius.${token}`;
  });

  if (changed && !src.includes(IMPORT_LINE)) {
    const importBlock = /^(import\s+['"][^'"]+['"];\s*\n)+/m;
    const m = src.match(importBlock);
    if (m) {
      const insertAt = m.index + m[0].length;
      src = src.slice(0, insertAt) + IMPORT_LINE + '\n' + src.slice(insertAt);
    } else {
      throw new Error(`No plain import line found to anchor the theme import in ${filePath} — insert it manually.`);
    }
  }

  if (changed) {
    stats.files++;
    stats.changedFiles.push(path.relative(LIB_DIR, filePath));
    if (!DRY_RUN) fs.writeFileSync(filePath, src, 'utf8');
  }
  return changed;
}

function main() {
  const files = walk(LIB_DIR);
  const stats = { files: 0, colors: 0, weights: 0, sizes: 0, radii: 0, unmapped: new Set(), changedFiles: [] };
  for (const file of files) migrateFile(file, stats);

  console.log(`${DRY_RUN ? '[DRY RUN] ' : ''}Files scanned: ${files.length}`);
  console.log(`Files changed: ${stats.files}`);
  console.log(`Colors replaced: ${stats.colors}`);
  console.log(`Font weights replaced: ${stats.weights}`);
  console.log(`Font sizes replaced: ${stats.sizes}`);
  console.log(`Radii replaced: ${stats.radii}`);

  if (stats.unmapped.size) {
    console.log(`\nUNMAPPED (left untouched — needs a manual look):`);
    for (const u of stats.unmapped) console.log(`  ${u}`);
    process.exitCode = 1;
  }
}

main();
