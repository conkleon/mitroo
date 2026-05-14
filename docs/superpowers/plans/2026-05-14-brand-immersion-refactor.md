# Brand Immersion Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor all app screens to match the login screen's professional/military design language — Playfair Display headlines, Space Grotesk body, white surfaces, dark gradient sidebar, and capsule chip components.

**Architecture:** Theme-first approach — update `main.dart` ThemeData to propagate fonts (Space Grotesk), colors (white surfaces), and component styles globally. Then manually update screens that use hardcoded colors/fonts. Finally, redesign the desktop sidebar with the login's gradient brand panel pattern.

**Tech Stack:** Flutter, Google Fonts (Playfair Display + Space Grotesk), custom painters

---

### Task 1: Theme Foundation — main.dart

**Files:**
- Modify: `frontend/lib/main.dart`

- [ ] **Step 1: Replace Inter with Space Grotesk, add Playfair Display**

Replace the `baseTextTheme` and add Playfair Display. Change `GoogleFonts.interTextTheme()` to `GoogleFonts.spaceGroteskTextTheme()`. Keep Playfair Display imported for headline use in individual screens.

```dart
// main.dart — MitrooApp.build()

// Replace:
final baseTextTheme = GoogleFonts.interTextTheme();

// With:
final baseTextTheme = GoogleFonts.spaceGroteskTextTheme();
```

- [ ] **Step 2: Update ThemeData — surfaces, appbar, cards, inputs**

Change scaffold background to white, update card theme for brand look, adjust appbar for white bg, update color scheme surface.

```dart
// In the ThemeData() call, replace the existing properties:

theme: ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  colorScheme: ColorScheme.fromSeed(
    seedColor: _primaryRed,
    brightness: Brightness.light,
    primary: _primaryRed,
    secondary: _accentRed,
    surface: Colors.white,
    onSurface: const Color(0xFF1A1C1E),
  ),
  scaffoldBackgroundColor: Colors.white,
  textTheme: baseTextTheme,
  cardTheme: CardThemeData(
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: Color(0xFFE5E7EB)),
    ),
    color: Colors.white,
    surfaceTintColor: Colors.transparent,
    margin: EdgeInsets.zero,
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: Colors.white,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
    titleTextStyle: GoogleFonts.playfairDisplay(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: const Color(0xFF1A1C1E),
      letterSpacing: -0.5,
    ),
    iconTheme: const IconThemeData(color: Color(0xFFC62828)),
  ),
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: Colors.white,
    elevation: 0,
    height: 56,
    indicatorColor: _primaryRed.withAlpha(25),
    labelTextStyle: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) {
        return baseTextTheme.labelSmall?.copyWith(
          color: _primaryRed,
          fontWeight: FontWeight.w600,
        );
      }
      return baseTextTheme.labelSmall?.copyWith(
        color: const Color(0xFF6B7280),
      );
    }),
    iconTheme: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) {
        return const IconThemeData(color: Color(0xFFC62828), size: 24);
      }
      return const IconThemeData(color: Color(0xFF6B7280), size: 24);
    }),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _primaryRed, width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: _primaryRed,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    ),
  ),
  floatingActionButtonTheme: FloatingActionButtonThemeData(
    backgroundColor: _primaryRed,
    foregroundColor: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    ),
  ),
  dividerTheme: const DividerThemeData(
    color: Color(0xFFE8ECF0),
    thickness: 1,
  ),
),
```

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/main.dart
git commit -m "refactor: apply brand theme foundation — Space Grotesk, white surfaces, card styling"
```

---

### Task 2: Dark Gradient Sidebar — shell_screen.dart

**Files:**
- Modify: `frontend/lib/shell_screen.dart`

- [ ] **Step 1: Replace the _DesktopSidebar background and styling**

The sidebar container becomes a dark gradient panel matching the login's `_BrandPanel`. Replace the entire `_DesktopSidebar` class with the new brand version.

```dart
// ── Brand sidebar constants ──
const _sidebarGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF6B0000), Color(0xFFC62828), Color(0xFFD84315)],
  stops: [0.0, 0.55, 1.0],
);

class _DesktopSidebar extends StatelessWidget {
  final AuthProvider auth;
  final bool showAdmin;
  final String currentPath;
  final String currentUri;
  final int selectedIndex;
  final List<String> mainPaths;

  const _DesktopSidebar({
    required this.auth,
    required this.showAdmin,
    required this.currentPath,
    required this.currentUri,
    required this.selectedIndex,
    required this.mainPaths,
  });

  @override
  Widget build(BuildContext context) {
    final isSysAdmin = auth.isAdmin;

    return Container(
      width: 240,
      decoration: const BoxDecoration(gradient: _sidebarGradient),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _CrossGridPainter())),
          // Diagonal accent stripe
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 3,
            child: Container(color: Colors.white.withAlpha(25)),
          ),
          Column(
            children: [
              // ── App header ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 16),
                child: Row(
                  children: [
                    Image.asset('assets/logo.png', height: 44),
                    const SizedBox(width: 10),
                    Text(
                      'R.C.D.',
                      style: GoogleFonts.spaceGrotesk(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // ── Navigation items ──
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  children: [
                    const _SidebarBrandSectionLabel('Κύριο Μενού'),
                    _BrandSidebarItem(
                      icon: Icons.miscellaneous_services_outlined,
                      selectedIcon: Icons.miscellaneous_services,
                      label: 'Υπηρεσίες',
                      selected: selectedIndex == 0,
                      onTap: () => context.go('/services'),
                    ),
                    _BrandSidebarItem(
                      icon: Icons.inventory_2_outlined,
                      selectedIcon: Icons.inventory_2,
                      label: 'Αντικείμενα',
                      selected: selectedIndex == 1,
                      onTap: () => context.go('/items'),
                    ),
                    _BrandSidebarItem(
                      icon: Icons.directions_car_outlined,
                      selectedIcon: Icons.directions_car,
                      label: 'Οχήματα',
                      selected: selectedIndex == 2,
                      onTap: () => context.go('/vehicles'),
                    ),
                    _BrandSidebarItem(
                      icon: Icons.chat_bubble_outline,
                      selectedIcon: Icons.chat_bubble,
                      label: 'Συνομιλία',
                      selected: currentPath.startsWith('/chat'),
                      onTap: () => context.go('/chat'),
                    ),
                    if (showAdmin) ...[
                      const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: _SidebarBrandSectionLabel('Διαχείριση'),
                      ),
                      _BrandSidebarItem(
                        icon: Icons.admin_panel_settings_outlined,
                        selectedIcon: Icons.admin_panel_settings,
                        label: 'Πίνακας Ελέγχου',
                        selected: currentPath == '/admin',
                        onTap: () => context.go('/admin'),
                      ),
                      if (isSysAdmin) ...[
                        _BrandSidebarItem(
                          icon: Icons.people_outline,
                          selectedIcon: Icons.people,
                          label: 'Χρήστες',
                          selected: currentPath.startsWith('/admin/users'),
                          onTap: () => context.push('/admin/users'),
                          indent: true,
                        ),
                        _BrandSidebarItem(
                          icon: Icons.business_outlined,
                          selectedIcon: Icons.business,
                          label: 'Τμήματα',
                          selected: currentPath.startsWith('/admin/departments'),
                          onTap: () => context.push('/admin/departments'),
                          indent: true,
                        ),
                        _BrandSidebarItem(
                          icon: Icons.school_outlined,
                          selectedIcon: Icons.school,
                          label: 'Ειδικότητες',
                          selected: currentPath.startsWith('/admin/specializations'),
                          onTap: () => context.push('/admin/specializations'),
                          indent: true,
                        ),
                      ],
                      if (auth.isMissionAdmin || isSysAdmin) ...[
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: _SidebarBrandSectionLabel('Διαχείριση Υπηρεσιών'),
                        ),
                        ..._buildDeptServiceItems(context, isSysAdmin),
                      ],
                    ],
                  ],
                ),
              ),
              // ── Profile footer ──
              Container(
                margin: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: InkWell(
                  onTap: () => context.push('/profile'),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 15,
                          backgroundColor: Colors.white.withAlpha(40),
                          child: Text(
                            auth.displayName.isNotEmpty
                                ? auth.displayName[0].toUpperCase()
                                : 'U',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                auth.displayName.isNotEmpty ? auth.displayName : 'Χρήστης',
                                style: GoogleFonts.spaceGrotesk(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                auth.isAdmin ? 'Διαχειριστής' : 'Εθελοντής',
                                style: GoogleFonts.spaceGrotesk(
                                  color: Colors.white.withAlpha(150),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 16, color: Colors.white54),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDeptServiceItems(BuildContext context, bool isSysAdmin) {
    List<Map<String, dynamic>> depts;
    if (isSysAdmin) {
      final deptProv = context.watch<DepartmentProvider>();
      if (deptProv.departments.isEmpty && !deptProv.loading) {
        Future.microtask(() => deptProv.fetchDepartments());
      }
      depts = deptProv.departments.cast<Map<String, dynamic>>();
    } else {
      depts = auth.missionAdminDepartments;
    }

    if (depts.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(left: 24, top: 4, bottom: 4),
          child: Text('Κανένα τμήμα',
              style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(120))),
        ),
      ];
    }

    return depts.map((dept) {
      final deptName = dept['name'] ?? 'Τμήμα';
      final deptId = dept['id'] as int;
      final path = '/admin/services?departmentId=$deptId&departmentName=${Uri.encodeComponent(deptName)}';
      final isActive = currentUri.contains('departmentId=$deptId');

      return _BrandSidebarItem(
        icon: Icons.folder_outlined,
        selectedIcon: Icons.folder,
        label: deptName,
        selected: isActive,
        onTap: () => context.go(path),
        indent: true,
      );
    }).toList();
  }
}
```

- [ ] **Step 2: Add the brand sidebar helper widgets**

Replace `_SidebarSectionLabel` and `_SidebarItem` with brand versions. Keep `_SidebarItemState` but update styling.

```dart
class _SidebarBrandSectionLabel extends StatelessWidget {
  final String label;
  const _SidebarBrandSectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 12, 4),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.spaceGrotesk(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
          color: Colors.white.withAlpha(120),
        ),
      ),
    );
  }
}

class _BrandSidebarItem extends StatefulWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool indent;

  const _BrandSidebarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.indent = false,
  });

  @override
  State<_BrandSidebarItem> createState() => _BrandSidebarItemState();
}

class _BrandSidebarItemState extends State<_BrandSidebarItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final bgColor = selected
        ? Colors.white.withAlpha(30)
        : _hovering
            ? Colors.white.withAlpha(12)
            : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: EdgeInsets.only(
            bottom: 2,
            left: widget.indent ? 12 : 0,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                widget.selected ? widget.selectedIcon : widget.icon,
                size: widget.indent ? 18 : 20,
                color: selected ? Colors.white : Colors.white.withAlpha(160),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.label,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: widget.indent ? 13 : 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? Colors.white : Colors.white.withAlpha(200),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Add the _CrossGridPainter (copy from login_screen.dart)**

Add the painter class at the bottom of `shell_screen.dart`. This is the same painter used in `login_screen.dart` — copy it exactly.

```dart
import 'dart:math' as math;

class _CrossGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(14)
      ..style = PaintingStyle.fill;

    void drawCross(double cx, double cy, double s, double angle) {
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(angle);
      final arm = s * 0.28;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: s, height: arm),
          const Radius.circular(3),
        ),
        paint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: arm, height: s),
          const Radius.circular(3),
        ),
        paint,
      );
      canvas.restore();
    }

    drawCross(size.width * 0.78, size.height * 0.12, 80, 0);
    drawCross(size.width * 0.12, size.height * 0.22, 45, math.pi / 12);
    drawCross(size.width * 0.65, size.height * 0.72, 110, math.pi / 8);
    drawCross(size.width * 0.35, size.height * 0.88, 50, 0);
    drawCross(size.width * 0.88, size.height * 0.52, 40, math.pi / 6);
    drawCross(size.width * 0.20, size.height * 0.58, 60, -math.pi / 10);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
```

- [ ] **Step 4: Add the import for GoogleFonts, math, and providers at top**

```dart
// Add to existing imports:
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;
```

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/shell_screen.dart
git commit -m "refactor: replace desktop sidebar with dark gradient brand panel"
```

---

### Task 3: Dashboard — Brand Typography

**Files:**
- Modify: `frontend/lib/screens/dashboard_screen.dart`

- [ ] **Step 1: Replace greeting text with Playfair Display, remove hardcoded bg color**

Remove `backgroundColor: const Color(0xFFF5F7FA)` from Scaffold (now inherited from theme). Change greeting and name to use Playfair Display. The stat cards and service list already use theme colors — they'll pick up the new theme automatically.

```dart
// In build():
// Remove: backgroundColor: const Color(0xFFF5F7FA),

// Change greeting:
Text(_greeting(), style: GoogleFonts.spaceGrotesk(
  fontSize: 14, color: const Color(0xFF6B7280),
)),

// Change name:
Text(name, style: GoogleFonts.playfairDisplay(
  fontSize: 28,
  fontWeight: FontWeight.w700,
  color: const Color(0xFF1A1C1E),
)),
```

Add the Google Fonts import:
```dart
import 'package:google_fonts/google_fonts.dart';
```

- [ ] **Step 2: Add a branded hero header at the top**

Add a compact gradient header strip with logo that introduces the dashboard, replacing the current simple logo+avatar row:

```dart
// Replace the top Row with logo+avatar:
// ── Brand header strip ──
Row(
  children: [
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6B0000), Color(0xFFC62828)],
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/logo.png', height: 24),
          const SizedBox(width: 8),
          Text('R.C.D.',
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    ),
    const Spacer(),
    GestureDetector(
      onTap: () => context.push('/profile'),
      child: CircleAvatar(
        radius: 18,
        backgroundColor: const Color(0xFFC62828),
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : 'U',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
    ),
  ],
),
```

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/screens/dashboard_screen.dart
git commit -m "refactor: apply brand typography and header to dashboard"
```

---

### Task 4: Services Screen — Cards, Chips, Calendar

**Files:**
- Modify: `frontend/lib/screens/services_screen.dart`

- [ ] **Step 1: Remove hardcoded background color, add Space Grotesk import**

Remove `backgroundColor: const Color(0xFFF5F7FA)` from the Scaffold. Add `import 'package:google_fonts/google_fonts.dart';`

- [ ] **Step 2: Add a page title with Playfair Display**

Before the top bar row, add a section title. Replace the empty left area of the top bar with a Playfair Display page title:

```dart
// Add before the top Row:
Padding(
  padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
  child: Row(
    children: [
      Container(
        width: 4, height: 22,
        decoration: BoxDecoration(
          color: const Color(0xFFC62828),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 10),
      Text(
        'Υπηρεσίες',
        style: GoogleFonts.playfairDisplay(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF1A1C1E),
          letterSpacing: -0.5,
        ),
      ),
    ],
  ),
),
const SizedBox(height: 12),
```

- [ ] **Step 3: Update hardcoded text styles and colors**

Replace all `tt.titleSmall` / `tt.titleMedium` usages that have `const Color(0xFF1F2937)` hardcoded in section headers with:

```dart
style: GoogleFonts.spaceGrotesk(
  fontSize: 15,
  fontWeight: FontWeight.w700,
  color: const Color(0xFF1A1C1E),
),
```

Replace the "Λίγα" / "Χωρίς" text with Space Grotesk references instead of default theme text.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/screens/services_screen.dart
git commit -m "refactor: apply brand styling to services screen"
```

---

### Task 5: Items & Vehicles Screens — Card + Chip Polish

**Files:**
- Modify: `frontend/lib/screens/items_screen.dart`
- Modify: `frontend/lib/screens/vehicles_screen.dart`

- [ ] **Step 1: Items screen — remove hardcoded background, add title header**

Remove `backgroundColor: const Color(0xFFF5F7FA)` from Scaffold. Add the Playfair Display page title header with red accent bar (same pattern as services screen):

```dart
// Replace the section header row with the branded version:
Row(
  children: [
    Container(
      width: 4, height: 22,
      decoration: BoxDecoration(
        color: const Color(0xFFC62828),
        borderRadius: BorderRadius.circular(2),
      ),
    ),
    const SizedBox(width: 10),
    Text(
      'Αντικείμενα',
      style: GoogleFonts.playfairDisplay(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF1A1C1E),
        letterSpacing: -0.5,
      ),
    ),
    const Spacer(),
    Text('${prov.totalItems} σύνολο',
      style: GoogleFonts.spaceGrotesk(
        fontSize: 13, color: const Color(0xFF6B7280),
      ),
    ),
  ],
),
```

Add `import 'package:google_fonts/google_fonts.dart';`

- [ ] **Step 2: Items screen — update the card list border**

Change the outer Card `BorderSide(color: Colors.grey.shade200)` to `const BorderSide(color: Color(0xFFE5E7EB))` and borderRadius from 12 to 14.

- [ ] **Step 3: Vehicles screen — remove hardcoded background, add title header**

Remove `backgroundColor: const Color(0xFFF5F7FA)` from Scaffold. Add the same branded section header pattern with Playfair Display title. Add Google Fonts import.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/screens/items_screen.dart frontend/lib/screens/vehicles_screen.dart
git commit -m "refactor: apply brand styling to items and vehicles screens"
```

---

### Task 6: Auth Screens — Forgot & Reset Password

**Files:**
- Modify: `frontend/lib/screens/forgot_password_screen.dart`
- Modify: `frontend/lib/screens/reset_password_screen.dart`

- [ ] **Step 1: Match login form styling**

Both screens: remove hardcoded background, replace page titles with Playfair Display, add Space Grotesk for body text.

Forgot password form header:
```dart
// Replace the lock icon + headline with:
Text('Επαναφορά Κωδικού',
  style: GoogleFonts.playfairDisplay(
    fontSize: 30,
    fontWeight: FontWeight.w700,
    color: const Color(0xFF1A1C1E),
    letterSpacing: -0.5,
  ),
),
const SizedBox(height: 6),
Text(
  'Εισάγετε το email του λογαριασμού σας.',
  style: GoogleFonts.spaceGrotesk(
    fontSize: 13,
    color: const Color(0xFF6B7280),
  ),
),
```

Same pattern for reset password. Both: add error banner matching login's `_ErrorBanner` style. Add `import 'package:google_fonts/google_fonts.dart';`.

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/screens/forgot_password_screen.dart frontend/lib/screens/reset_password_screen.dart
git commit -m "refactor: match forgot/reset password screens to login style"
```

---

### Task 7: Remaining Screens — Bulk Brand Polish

**Files:**
- Modify: `frontend/lib/screens/profile_screen.dart`
- Modify: `frontend/lib/screens/admin_panel_screen.dart`
- Modify: `frontend/lib/screens/manage_departments_screen.dart`
- Modify: `frontend/lib/screens/manage_services_screen.dart`
- Modify: `frontend/lib/screens/manage_specializations_screen.dart`
- Modify: `frontend/lib/screens/manage_users_screen.dart`
- Modify: `frontend/lib/screens/create_service_screen.dart`
- Modify: `frontend/lib/screens/department_detail_screen.dart`
- Modify: `frontend/lib/screens/user_detail_screen.dart`
- Modify: `frontend/lib/screens/service_detail_screen.dart`
- Modify: `frontend/lib/screens/item_detail_screen.dart`
- Modify: `frontend/lib/screens/vehicle_detail_screen.dart`
- Modify: `frontend/lib/screens/specialization_detail_screen.dart`
- Modify: `frontend/lib/screens/past_services_screen.dart`
- Modify: `frontend/lib/screens/training_application_screen.dart`
- Modify: `frontend/lib/screens/training_applications_review_screen.dart`
- Modify: `frontend/lib/screens/items_csv_screen.dart`
- Modify: `frontend/lib/screens/scanner_screen.dart`
- Modify: `frontend/lib/widgets/my_equipment_sheet.dart`
- Modify: `frontend/lib/screens/chat_screen.dart`
- Modify: `frontend/lib/screens/chat_detail_screen.dart`
- Modify: `frontend/lib/screens/chat_settings_screen.dart`
- Modify: `frontend/lib/screens/create_chat_screen.dart`

- [ ] **Step 1: Batch remove hardcoded `backgroundColor: const Color(0xFFF5F7FA)` from all Scaffolds**

Search every file for `backgroundColor: const Color(0xFFF5F7FA)` and remove those lines. The theme's `scaffoldBackgroundColor: Colors.white` will apply automatically.

- [ ] **Step 2: Replace remaining `Colors.grey.shade*` hardcoded colors**

Search for patterns like `Colors.grey.shade100`, `Colors.grey.shade200`, `Colors.grey.shade300`, `Colors.grey.shade400`, `Colors.grey.shade50` in screen files and replace:
- `Colors.grey.shade200` → `Color(0xFFE5E7EB)` (border)
- `Colors.grey.shade100` → `Color(0xFFF3F4F6)` (subtle bg)
- `Colors.grey.shade300` → `Color(0xFFD1D5DB)` (disabled)
- `Colors.grey.shade400` → `Color(0xFF9CA3AF)` (muted icon)
- `Colors.grey.shade50` → `Color(0xFFF9FAFB)` (light surface)

- [ ] **Step 3: Add Playfair Display page titles and Space Grotesk imports**

For each screen, add `import 'package:google_fonts/google_fonts.dart';` if not present. Where screens have prominent titles, wrap them in `GoogleFonts.playfairDisplay()`.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/screens/ frontend/lib/widgets/
git commit -m "refactor: remove hardcoded colors, apply brand fonts across all remaining screens"
```

---

### Task 8: Verify and Polish

**Files:**
- None (verification only)

- [ ] **Step 1: Verify the app builds without errors**

```bash
cd frontend
flutter analyze
```
Expected: No errors. Warnings may exist (pre-existing).

- [ ] **Step 2: Run the app and verify visual consistency**

```bash
flutter run -d chrome
```
Check: sidebar gradient visible, Playfair headlines on dashboard/services/items, white backgrounds throughout, red accent strips on cards, Space Grotesk body text.

- [ ] **Step 3: Commit any final polish**

```bash
git add -A
git commit -m "chore: final brand immersion polish"
```
