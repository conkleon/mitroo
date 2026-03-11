import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_client.dart';

/// Reusable image gallery card for entity detail screens.
/// Shows thumbnails in a grid, supports upload via file picker and delete.
class ImageGalleryCard extends StatefulWidget {
  /// The query parameter key (e.g. 'itemId', 'vehicleId').
  final String entityParam;

  /// The entity ID value.
  final int entityId;

  /// Whether the current user can manage (upload/delete) images.
  final bool canManage;

  const ImageGalleryCard({
    super.key,
    required this.entityParam,
    required this.entityId,
    required this.canManage,
  });

  @override
  State<ImageGalleryCard> createState() => _ImageGalleryCardState();
}

class _ImageGalleryCardState extends State<ImageGalleryCard> {
  final _api = ApiClient();
  List<dynamic> _files = [];
  bool _loading = true;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _api.get('/files?${widget.entityParam}=${widget.entityId}&imagesOnly=true');
      if (res.statusCode == 200 && mounted) {
        final body = jsonDecode(res.body);
        setState(() {
          _files = (body is Map ? body['data'] : body) as List;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _uploadImage() async {
    // On web, go straight to file picker; on mobile, offer camera option
    if (kIsWeb) {
      _pickFromGallery();
    } else {
      final choice = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Κάμερα'),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Συλλογή'),
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
            ],
          ),
        ),
      );
      if (choice == null || !mounted) return;
      if (choice == 'camera') {
        _pickFromCamera();
      } else {
        _pickFromGallery();
      }
    }
  }

  Future<void> _pickFromCamera() async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(source: ImageSource.camera);
    if (photo == null || !mounted) return;

    final bytes = await photo.readAsBytes();
    await _doUpload(bytes, photo.name);
  }

  Future<void> _pickFromGallery() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) return;

    await _doUpload(file.bytes!, file.name);
  }

  Future<void> _doUpload(List<int> bytes, String fileName) async {
    setState(() => _uploading = true);

    try {
      final res = await _api.uploadFile(
        '/files?${widget.entityParam}=${widget.entityId}',
        fileBytes: bytes,
        fileName: fileName,
      );
      if (res.statusCode == 201 && mounted) {
        await _load();
      } else if (mounted) {
        final body = jsonDecode(res.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(body['error'] ?? 'Σφάλμα μεταφόρτωσης')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Σφάλμα: $e')),
        );
      }
    }

    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _deleteFile(int fileId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Διαγραφή Εικόνας'),
        content: const Text('Είστε σίγουροι;'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Άκυρο')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            child: const Text('Διαγραφή'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final res = await _api.delete('/files/$fileId');
      if (res.statusCode == 204 && mounted) {
        setState(() => _files.removeWhere((f) => f['id'] == fileId));
      }
    } catch (_) {}
  }

  String _imageUrl(Map<String, dynamic> file, {bool thumbnail = false}) {
    final path = thumbnail && file['thumbnailPath'] != null
        ? file['thumbnailPath'] as String
        : file['filePath'] as String;
    return '${ApiClient.uploadsBaseUrl}$path';
  }

  void _openFullScreen(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreenGallery(
          files: _files.cast<Map<String, dynamic>>(),
          initialIndex: index,
          canManage: widget.canManage,
          onDelete: _deleteFile,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withAlpha(15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.photo_library_outlined, size: 18, color: Color(0xFF3B82F6)),
                ),
                const SizedBox(width: 10),
                Text('Εικόνες', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                if (_files.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withAlpha(15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_files.length}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF3B82F6), fontWeight: FontWeight.w700),
                    ),
                  ),
                if (widget.canManage) ...[
                  const SizedBox(width: 8),
                  _uploading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _uploadImage,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3B82F6).withAlpha(10),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF3B82F6).withAlpha(30)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add_photo_alternate_outlined, size: 14, color: Color(0xFF3B82F6)),
                                  SizedBox(width: 4),
                                  Text(
                                    'Προσθήκη',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF3B82F6)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                ],
              ],
            ),
            const SizedBox(height: 14),

            // Body
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
            else if (_files.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.photo_outlined, color: Colors.grey.shade400, size: 28),
                      const SizedBox(height: 6),
                      Text('Δεν υπάρχουν εικόνες', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                    ],
                  ),
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _files.length,
                itemBuilder: (ctx, i) {
                  final file = _files[i] as Map<String, dynamic>;
                  return GestureDetector(
                    onTap: () => _openFullScreen(i),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            _imageUrl(file, thumbnail: true),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.grey.shade200,
                              child: Icon(Icons.broken_image, color: Colors.grey.shade400),
                            ),
                          ),
                        ),
                        if (widget.canManage)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => _deleteFile(file['id'] as int),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withAlpha(120),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close, size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen image viewer with swipe navigation.
class _FullScreenGallery extends StatefulWidget {
  final List<Map<String, dynamic>> files;
  final int initialIndex;
  final bool canManage;
  final Future<void> Function(int) onDelete;

  const _FullScreenGallery({
    required this.files,
    required this.initialIndex,
    required this.canManage,
    required this.onDelete,
  });

  @override
  State<_FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<_FullScreenGallery> {
  late PageController _controller;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _controller = PageController(initialPage: _current);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _imageUrl(Map<String, dynamic> file) {
    return '${ApiClient.uploadsBaseUrl}${file['filePath']}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_current + 1} / ${widget.files.length}',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          if (widget.canManage)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await widget.onDelete(widget.files[_current]['id'] as int);
                if (mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.files.length,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (ctx, i) {
          return InteractiveViewer(
            child: Center(
              child: Image.network(
                _imageUrl(widget.files[i]),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white54, size: 64),
              ),
            ),
          );
        },
      ),
    );
  }
}
