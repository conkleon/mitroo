import 'dart:io';
import 'dart:typed_data';

Future<void> downloadFile(Uint8List bytes, String filename) async {
  // Save to a temporary file for native platforms
  final dir = Directory.systemTemp;
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes);
}
