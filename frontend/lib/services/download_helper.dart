import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;

// Conditional imports: web vs IO
import 'download_helper_stub.dart'
    if (dart.library.html) 'download_helper_web.dart'
    if (dart.library.io) 'download_helper_io.dart' as impl;

/// Downloads [bytes] as a file with the given [filename].
/// On web, triggers a browser download. On native, saves to downloads folder.
Future<void> downloadFile(Uint8List bytes, String filename) {
  return impl.downloadFile(bytes, filename);
}
