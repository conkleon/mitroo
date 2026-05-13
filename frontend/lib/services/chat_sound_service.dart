import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

// Tiny 8-bit mono WAV — two ascending tones (E5→A5), ~0.3s.
// Generated programmatically so no audio file is needed.
Uint8List _buildChimeWav() {
  const sampleRate = 44100;
  const duration = 0.3; // seconds
  final numSamples = (sampleRate * duration).round();
  // 8-bit mono PCM WAV: 44-byte header + data
  final dataSize = numSamples;
  final out = ByteData(44 + dataSize);

  // RIFF header
  out.setUint8(0, 0x52); // R
  out.setUint8(1, 0x49); // I
  out.setUint8(2, 0x46); // F
  out.setUint8(3, 0x46); // F
  out.setUint32(4, 36 + dataSize, Endian.little);
  out.setUint8(8, 0x57); // W
  out.setUint8(9, 0x41); // A
  out.setUint8(10, 0x56); // V
  out.setUint8(11, 0x45); // E

  // fmt chunk
  out.setUint8(12, 0x66); // f
  out.setUint8(13, 0x6D); // m
  out.setUint8(14, 0x74); // t
  out.setUint8(15, 0x20); // space
  out.setUint32(16, 16, Endian.little); // chunk size
  out.setUint16(20, 1, Endian.little); // PCM
  out.setUint16(22, 1, Endian.little); // mono
  out.setUint32(24, sampleRate, Endian.little);
  out.setUint32(28, sampleRate, Endian.little); // byte rate
  out.setUint16(32, 1, Endian.little); // block align
  out.setUint16(34, 8, Endian.little); // bits per sample

  // data chunk
  out.setUint8(36, 0x64); // d
  out.setUint8(37, 0x61); // a
  out.setUint8(38, 0x74); // t
  out.setUint8(39, 0x61); // a
  out.setUint32(40, dataSize, Endian.little);

  // Two-tone chime: E5 (659.25 Hz) + A5 (880 Hz), amplitude envelope
  for (var i = 0; i < numSamples; i++) {
    final t = i / sampleRate;
    double amp;
    if (t < 0.12) {
      // E5 tone, quick decay
      amp = (1.0 - t / 0.12) * 0.6;
      final sample = (amp * _sin(2 * 3.14159 * 659.25 * t) * 127 + 128).round();
      out.setUint8(44 + i, sample.clamp(0, 255));
    } else {
      // A5 tone, fade in then out
      final localT = t - 0.10; // slight overlap
      amp = localT < 0.15 ? localT / 0.15 * 0.6 : (1.0 - (localT - 0.15) / 0.15) * 0.6;
      if (amp < 0) amp = 0;
      final sample = (amp * _sin(2 * 3.14159 * 880.0 * t) * 127 + 128).round();
      out.setUint8(44 + i, sample.clamp(0, 255));
    }
  }

  return out.buffer.asUint8List();
}

double _sin(double x) {
  // Taylor series approximation, good enough for simple tones
  x = x % (2 * 3.14159);
  double result = x;
  double term = x;
  for (var n = 1; n < 10; n++) {
    term *= -x * x / ((2 * n) * (2 * n + 1));
    result += term;
  }
  return result;
}

/// Lightweight notification sound service.
///
/// Plays a built-in two-tone chime by default. Call [setCustomSound] with a
/// path like `'assets/sounds/alert.mp3'` to use your own file instead.
class ChatSoundService {
  static final ChatSoundService _instance = ChatSoundService._();
  factory ChatSoundService() => _instance;
  ChatSoundService._();

  String? _customPath;
  String? _dataUri;

  String get _uri {
    _dataUri ??= 'data:audio/wav;base64,${base64Encode(_buildChimeWav())}';
    return _customPath ?? _dataUri!;
  }

  /// Point to a custom audio file (path relative to the web root, e.g.
  /// `'assets/sounds/chat_notification.mp3'`).
  void setCustomSound(String path) {
    _customPath = path;
  }

  void play() {
    try {
      final audio = html.AudioElement(_uri);
      audio.play().catchError((_) {});
    } catch (_) {}
  }
}
