import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/item_provider.dart';
import '../providers/category_provider.dart';
import '../providers/department_provider.dart';

/// Screen for exporting and importing items via CSV.
class ItemsCsvScreen extends StatefulWidget {
  const ItemsCsvScreen({super.key});

  @override
  State<ItemsCsvScreen> createState() => _ItemsCsvScreenState();
}

class _ItemsCsvScreenState extends State<ItemsCsvScreen> {
  final _importCtrl = TextEditingController();
  String? _exportedCsv;
  String? _pickedFileName;
  bool _exporting = false;
  bool _importing = false;
  Map<String, dynamic>? _importResult;
  int? _selectedImportDeptId;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      context.read<CategoryProvider>().fetchCategories();
      context.read<DepartmentProvider>().fetchDepartments();
    });
  }

  // ── Export ──

  Future<void> _exportCsv({bool template = false}) async {
    setState(() {
      _exporting = true;
      if (!template) _exportedCsv = null;
    });
    final csv = await context.read<ItemProvider>().exportCsv(template: template);
    if (mounted) {
      setState(() => _exporting = false);
      if (template) {
        if (csv != null) {
          _exportedCsv = csv;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Αποτυχία λήψης προτύπου')),
          );
        }
      } else {
        _exportedCsv = csv;
        if (csv == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Αποτυχία εξαγωγής CSV')),
          );
        }
      }
    }
  }

  Future<void> _copyCsv() async {
    if (_exportedCsv != null) {
      await Clipboard.setData(ClipboardData(text: _exportedCsv!));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Αντιγράφηκε στο πρόχειρο')),
        );
      }
    }
  }

  // ── CSV parsing ──

  /// Parse a single CSV line into fields, respecting double-quoted values
  /// that may contain commas and escaped quotes ("").
  List<String> _splitCsvLine(String line) {
    final fields = <String>[];
    final buf = StringBuffer();
    bool inQuotes = false;
    for (int i = 0; i < line.length; i++) {
      final c = line[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            buf.write('"');
            i++; // skip escaped quote
          } else {
            inQuotes = false;
          }
        } else {
          buf.write(c);
        }
      } else {
        if (c == '"') {
          inQuotes = true;
        } else if (c == ',') {
          fields.add(buf.toString().trim());
          buf.clear();
        } else {
          buf.write(c);
        }
      }
    }
    fields.add(buf.toString().trim());
    return fields;
  }

  List<Map<String, dynamic>> _parseCsv(String raw) {
    final lines = raw.trim().split('\n');
    if (lines.length < 2) return [];
    final headers = _splitCsvLine(lines.first);
    final rows = <Map<String, dynamic>>[];
    for (var i = 1; i < lines.length; i++) {
      final values = _splitCsvLine(lines[i]);
      if (values.length != headers.length) continue;
      final row = <String, dynamic>{};
      for (var j = 0; j < headers.length; j++) {
        final key = headers[j];
        final val = values[j];
        if (val.isEmpty) {
          row[key] = null;
        } else if (key == 'isContainer' || key == 'availableForAssignment') {
          row[key] = val.toLowerCase() == 'true';
        } else if (key == 'quantity') {
          row[key] = int.tryParse(val) ?? 1;
        } else {
          row[key] = val;
        }
      }
      rows.add(row);
    }
    return rows;
  }

  // ── File picker ──

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt'],
        withData: true,
      );
      if (result != null && result.files.single.bytes != null) {
        final content = utf8.decode(result.files.single.bytes!);
        setState(() {
          _importCtrl.text = content;
          _pickedFileName = result.files.single.name;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Αποτυχία ανάγνωσης αρχείου')),
        );
      }
    }
  }

  // ── Import ──

  Future<void> _importCsv() async {
    if (_selectedImportDeptId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Επίλεξε τμήμα πρώτα')),
      );
      return;
    }
    final text = _importCtrl.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Επίλεξε αρχείο ή επικόλλησε CSV')),
      );
      return;
    }
    final rows = _parseCsv(text);
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Δεν βρέθηκαν έγκυρες γραμμές')),
      );
      return;
    }
    setState(() {
      _importing = true;
      _importResult = null;
    });
    final result = await context
        .read<ItemProvider>()
        .importCsv(_selectedImportDeptId!, rows);
    if (mounted) {
      setState(() {
        _importing = false;
        _importResult = result;
      });
    }
  }

  @override
  void dispose() {
    _importCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final depts = context.watch<DepartmentProvider>().departments;

    return Scaffold(
      appBar: AppBar(title: const Text('Ρυθμίσεις Αντικειμένων')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Category management section ──
          _buildCategorySection(tt, cs),
          const SizedBox(height: 20),
          // ── Export section ──
          _buildExportCard(tt, cs),
          const SizedBox(height: 20),
          // ── Import section ──
          _buildImportCard(tt, cs, depts),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // ── Export card ──

  Widget _buildExportCard(TextTheme tt, ColorScheme cs) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primary.withAlpha(15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.file_download_outlined, size: 20, color: cs.primary),
                ),
                const SizedBox(width: 10),
                Text('Εξαγωγή', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Κατέβασε όλα τα αντικείμενα σε CSV ή κατέβασε ένα πρότυπο για εισαγωγή.',
              style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280)),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _exporting ? null : () => _exportCsv(),
                    icon: _exporting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.download, size: 18),
                    label: const Text('Εξαγωγή όλων'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _exporting ? null : () => _exportCsv(template: true),
                    icon: _exporting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.description_outlined, size: 18),
                    label: const Text('Πρότυπο CSV'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            if (_exportedCsv != null) ...[
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  scrollDirection: Axis.horizontal,
                  child: SelectableText(
                    _exportedCsv!,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _copyCsv,
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Αντιγραφή'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Import card ──

  Widget _buildImportCard(TextTheme tt, ColorScheme cs, List<dynamic> depts) {
    // Pre-select first department if none selected yet
    if (_selectedImportDeptId == null && depts.isNotEmpty) {
      _selectedImportDeptId = depts.first['id'] as int;
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669).withAlpha(15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.file_upload_outlined, size: 20, color: Color(0xFF059669)),
                ),
                const SizedBox(width: 10),
                Text('Εισαγωγή', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Επίλεξε τμήμα, μετά επίλεξε αρχείο CSV ή επικόλλησε δεδομένα για μαζική δημιουργία αντικειμένων.',
              style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280)),
            ),
            const SizedBox(height: 16),
            // Department dropdown
            DropdownButtonFormField<int>(
              value: _selectedImportDeptId,
              decoration: InputDecoration(
                labelText: 'Τμήμα',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Color(0xFFD1D5DB)),
                ),
              ),
              items: depts
                  .map<DropdownMenuItem<int>>((d) => DropdownMenuItem(
                        value: d['id'] as int,
                        child: Text(d['name'] ?? ''),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _selectedImportDeptId = v),
            ),
            const SizedBox(height: 14),
            // File picker button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.folder_open, size: 18),
                label: Text(_pickedFileName ?? 'Επιλογή αρχείου CSV'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 14),
            // Divider with "or paste"
            Row(
              children: [
                Expanded(child: Divider(color: Color(0xFFD1D5DB))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('ή επικόλλησε', style: tt.bodySmall?.copyWith(color: const Color(0xFF9CA3AF))),
                ),
                Expanded(child: Divider(color: Color(0xFFD1D5DB))),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _importCtrl,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: 'name,description,barCode,location,categoryName,isContainer,quantity,expirationDate\n'
                    '"Παράδειγμα","Περιγραφή","BC-001","Αποθήκη Α","Αναλώσιμα",false,1,2026-12-31',
                filled: true,
                fillColor: Color(0xFFF3F4F6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _importing ? null : _importCsv,
                icon: _importing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.upload, size: 18),
                label: Text(_importing ? 'Εισαγωγή...' : 'Εισαγωγή CSV'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            if (_importResult != null) ...[
              const SizedBox(height: 14),
              if (_importResult!.containsKey('created'))
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669).withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Color(0xFF059669), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Δημιουργήθηκαν ${_importResult!['created']} αντικείμενα',
                          style: const TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_importResult!.containsKey('errors') && (_importResult!['errors'] as List).isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.warning_amber, color: Color(0xFFDC2626), size: 20),
                          SizedBox(width: 8),
                          Text('Σφάλματα:', style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.w500)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ...(_importResult!['errors'] as List).map((e) => Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('• $e', style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12)),
                          )),
                    ],
                  ),
                ),
              ],
              if (_importResult!.containsKey('error'))
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_importResult!['error']}',
                          style: const TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Category management card ──

  Widget _buildCategorySection(TextTheme tt, ColorScheme cs) {
    final catProv = context.watch<CategoryProvider>();
    final depts = context.watch<DepartmentProvider>().departments;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primary.withAlpha(15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.category_outlined, size: 20, color: cs.primary),
                ),
                const SizedBox(width: 10),
                Text('Κατηγορίες', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: () => _showCreateCategoryDialog(depts),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Νέα'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Οι κατηγορίες είναι ανά τμήμα. Κάθε τμήμα μπορεί να έχει τις δικές του.',
              style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280)),
            ),
            const SizedBox(height: 12),
            if (catProv.loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (catProv.categories.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                alignment: Alignment.center,
                child: Text('Δεν υπάρχουν κατηγορίες', style: tt.bodyMedium?.copyWith(color: const Color(0xFF9CA3AF))),
              )
            else
              ...catProv.categories.map((cat) {
                final dept = cat['department'];
                final itemCount = cat['_count']?['items'] ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 1),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    dense: true,
                    title: Text(cat['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text(
                      '${dept?['name'] ?? ''} · $itemCount αντικείμεν${itemCount == 1 ? 'ο' : 'α'}',
                      style: tt.bodySmall?.copyWith(color: const Color(0xFF6B7280)),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () => _showRenameCategoryDialog(cat),
                          tooltip: 'Μετονομασία',
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFDC2626)),
                          onPressed: () => _confirmDeleteCategory(cat),
                          tooltip: 'Διαγραφή',
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  void _showCreateCategoryDialog(List<dynamic> depts) {
    final nameCtrl = TextEditingController();
    int? selectedDeptId = depts.isNotEmpty ? depts.first['id'] as int : null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Νέα Κατηγορία'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Όνομα', border: OutlineInputBorder()),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: selectedDeptId,
                decoration: const InputDecoration(labelText: 'Τμήμα', border: OutlineInputBorder()),
                items: depts
                    .map<DropdownMenuItem<int>>((d) => DropdownMenuItem(
                          value: d['id'] as int,
                          child: Text(d['name'] ?? ''),
                        ))
                    .toList(),
                onChanged: (v) => setSt(() => selectedDeptId = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Άκυρο')),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty || selectedDeptId == null) return;
                final err = await context.read<CategoryProvider>().create(nameCtrl.text.trim(), selectedDeptId!);
                if (ctx.mounted) Navigator.pop(ctx);
                if (err != null && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                }
              },
              child: const Text('Δημιουργία'),
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameCategoryDialog(Map<String, dynamic> cat) {
    final nameCtrl = TextEditingController(text: cat['name'] ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Μετονομασία'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Όνομα', border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Άκυρο')),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final err = await context.read<CategoryProvider>().update(cat['id'] as int, nameCtrl.text.trim());
              if (ctx.mounted) Navigator.pop(ctx);
              if (err != null && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
              }
            },
            child: const Text('Αποθήκευση'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteCategory(Map<String, dynamic> cat) {
    final itemCount = cat['_count']?['items'] ?? 0;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Διαγραφή Κατηγορίας'),
        content: Text(
          itemCount > 0
              ? 'Η κατηγορία "${cat['name']}" έχει $itemCount αντικείμενα. Τα αντικείμενα δεν θα διαγραφούν, απλά θα χάσουν την κατηγορία τους.'
              : 'Διαγραφή της κατηγορίας "${cat['name']}";',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Άκυρο')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Color(0xFFDC2626)),
            onPressed: () async {
              Navigator.pop(ctx);
              final err = await context.read<CategoryProvider>().deleteCategory(cat['id'] as int);
              if (err != null && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
              }
            },
            child: const Text('Διαγραφή'),
          ),
        ],
      ),
    );
  }
}
