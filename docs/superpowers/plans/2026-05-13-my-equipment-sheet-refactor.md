# My Equipment Sheet Refactor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor `MyEquipmentSheet` with polished item cards and two separate, prominent scan entry points (QR Code + Barcode) replacing the single generic scan button.

**Architecture:** All changes are in `my_equipment_sheet.dart`. The `ScannerScreen` already auto-detects both QR and barcode formats, so both scan buttons open the same scanner directly — no dialog needed. The existing scan result handling distinguishes QR (→ item detail) from barcode (→ search by barcode).

**Tech Stack:** Flutter/Dart, no new dependencies

---

### Task 1: Add scan helper method and refactor scan button into two panels

**Files:**
- Modify: `frontend/lib/screens/my_equipment_sheet.dart`

- [ ] **Step 1: Add a `_handleScan` helper method to the state class**

Add this method right after `_selfAssignItem` (around line 164):

```dart
Future<void> _handleScan() async {
  final result = await Navigator.of(context).push<ScanResult>(
    MaterialPageRoute(builder: (_) => const ScannerScreen()),
  );
  if (result == null || !mounted) return;

  final parsedId = int.tryParse(result.value);
  if (result.isQr || (parsedId != null && result.value == parsedId.toString())) {
    if (parsedId != null) {
      Navigator.pop(context);
      ItemDetailScreen.show(context, parsedId);
    }
  } else {
    setState(() => _searchLoading = true);
    try {
      final res = await widget.api.get(
        '/items/barcode/${Uri.encodeComponent(result.value)}',
      );
      if (mounted) {
        setState(() {
          _searchResults = res.statusCode == 200
              ? jsonDecode(res.body) as List<dynamic>
              : [];
          _searchLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _searchLoading = false);
    }
  }
}
```

- [ ] **Step 2: Replace the single scan `IconButton.filled` with the two scan panels**

In `_buildEquipmentSearch`, replace the current `Row` containing the search field + scan button (lines 513-575) with this:

```dart
// Search bar
TextField(
  decoration: InputDecoration(
    hintText: 'Αναζήτηση με όνομα ή barcode...',
    prefixIcon: const Icon(Icons.search),
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10)),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(
        horizontal: 12, vertical: 10),
  ),
  onChanged: (v) {
    _searchQuery = v;
    _fetchAvailableItems(v);
  },
),
const SizedBox(height: 12),

// Two separate scan panels
_scanPanel(
  icon: Icons.qr_code,
  color: const Color(0xFF6366F1),
  title: 'Σάρωση QR Code',
  subtitle: 'Σάρωση κωδικού QR με κάμερα',
  onTap: _handleScan,
),
const SizedBox(height: 10),
_scanPanel(
  icon: Icons.barcode_reader,
  color: const Color(0xFF0D9488),
  title: 'Σάρωση Barcode',
  subtitle: 'Σάρωση barcode με κάμερα',
  onTap: _handleScan,
),
const SizedBox(height: 12),
```

- [ ] **Step 3: Add the `_scanPanel` helper widget method**

Add this at the end of the `_MyEquipmentSheetState` class (before the closing `}`):

```dart
Widget _scanPanel({
  required IconData icon,
  required Color color,
  required String title,
  required String subtitle,
  required VoidCallback onTap,
}) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: color.withAlpha(15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withAlpha(76)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: color.withAlpha(180)),
          ],
        ),
      ),
    ),
  );
}
```

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/screens/my_equipment_sheet.dart
git commit -m "refactor: replace single scan button with separate QR + Barcode scan panels"
```

---

### Task 2: Polish "My Equipment" item cards

**Files:**
- Modify: `frontend/lib/screens/my_equipment_sheet.dart`

- [ ] **Step 1: Replace the `_buildMyEquipment` method's item builder**

Replace the item card inside `_buildMyEquipment` (lines 652-739, the `Container` returned by `itemBuilder`) with this refined version:

```dart
final isExpired = item['expirationDate'] != null &&
    DateTime.tryParse(item['expirationDate'] ?? '')
            ?.isBefore(DateTime.now()) ==
        true;

return Container(
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(
    color: isExpired ? Colors.red.shade50 : Colors.white,
    border: Border.all(
      color: isExpired ? Colors.red.shade200 : const Color(0xFFE5E7EB),
    ),
    borderRadius: BorderRadius.circular(12),
  ),
  child: Row(
    children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: cs.primary.withAlpha(20),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          item['isContainer'] == true
              ? Icons.inventory_2
              : Icons.build_outlined,
          color: cs.primary,
          size: 20,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item['name'] ?? '',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (item['barCode'] != null || item['location'] != null) ...[
              const SizedBox(height: 3),
              Text(
                [item['barCode'], item['location']]
                    .whereType<String>()
                    .where((s) => s.isNotEmpty)
                    .join(' · '),
                style: tt.bodySmall?.copyWith(
                  color: const Color(0xFF6B7280),
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
      if (isExpired)
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Text(
              'Έληξε',
              style: TextStyle(
                color: Colors.red.shade700,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      IconButton(
        icon: const Icon(Icons.open_in_new, size: 18),
        tooltip: 'Λεπτομέρειες',
        color: const Color(0xFF6B7280),
        onPressed: () {
          Navigator.pop(context);
          ItemDetailScreen.show(context, itemId);
        },
        visualDensity: VisualDensity.compact,
      ),
      IconButton(
        icon: isBusy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(Icons.assignment_return,
                size: 18, color: Colors.red.shade600),
        tooltip: 'Επιστροφή',
        onPressed: isBusy ? null : () => _returnItem(item),
        visualDensity: VisualDensity.compact,
      ),
    ],
  ),
);
```

- [ ] **Step 2: Update the empty state in `_buildMyEquipment`**

Replace the empty state call (line 638-639) with a more polished version:

```dart
if (_items.isEmpty) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF059669).withAlpha(12),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_outline,
            size: 40,
            color: Color(0xFF059669),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Κανένας εξοπλισμός',
          style: tt.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: const Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Πατήστε "Λήψη" για να αναζητήσετε διαθέσιμο εξοπλισμό',
          style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280)),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}
```

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/screens/my_equipment_sheet.dart
git commit -m "refactor: polish my-equipment item cards with refined styling"
```

---

### Task 3: Polish equipment search empty & loading states

**Files:**
- Modify: `frontend/lib/screens/my_equipment_sheet.dart`

- [ ] **Step 1: Replace the search empty state**

Replace `_emptyState(Icons.search_off, 'Δεν βρέθηκαν διαθέσιμα αντικείμενα', tt)` at line ~584 with:

```dart
Padding(
  padding: const EdgeInsets.symmetric(vertical: 32),
  child: Column(
    children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.search_off, size: 40, color: Colors.grey.shade400),
      ),
      const SizedBox(height: 16),
      Text(
        'Δεν βρέθηκαν διαθέσιμα αντικείμενα',
        style: tt.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: const Color(0xFF374151),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'Δοκιμάστε διαφορετικό όρο αναζήτησης ή σαρώστε έναν κωδικό',
        style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280)),
        textAlign: TextAlign.center,
      ),
    ],
  ),
)
```

- [ ] **Step 2: Update the loading spinner**

Replace the `CircularProgressIndicator` at line ~578-582 with a centered one inside a padded container:

```dart
if (_searchLoading)
  const Padding(
    padding: EdgeInsets.symmetric(vertical: 40),
    child: Center(child: CircularProgressIndicator()),
  )
```

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/screens/my_equipment_sheet.dart
git commit -m "refactor: polish search empty and loading states in equipment sheet"
```

---

### Task 4: Verify and finalize

- [ ] **Step 1: Run Flutter analyze to check for errors**

```bash
cd frontend && flutter analyze lib/screens/my_equipment_sheet.dart
```

Expected: No issues found.

- [ ] **Step 2: Verify no dead code remains**

The import `import 'scanner_screen.dart';` is still needed for `ScanResult` and `ScannerScreen`. `showScanChoiceDialog` is no longer called in this file after Task 1 — that's fine, the import stays as-is.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/screens/my_equipment_sheet.dart
git commit -m "chore: clean up unused imports in equipment sheet"
```
