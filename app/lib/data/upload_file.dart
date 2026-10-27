import 'dart:typed_data';

/// Bytes ready to send as a multipart part. Works the same on web and mobile.
final class UploadFile {
  const UploadFile({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String filename;
  final String mimeType;
}

/// Where a proof photo came from. Upload fallback is always flagged for review.
enum CaptureMode {
  live,
  uploadFallback;

  String get wire => switch (this) {
    live => 'live',
    uploadFallback => 'upload_fallback',
  };
}

/// What the device knew at the moment the shutter fired.
final class CaptureMeta {
  const CaptureMeta({
    required this.capturedAt,
    required this.mode,
    this.lat,
    this.lng,
    this.accuracyM,
  });

  final DateTime capturedAt;
  final CaptureMode mode;
  final double? lat;
  final double? lng;
  final double? accuracyM;

  bool get hasFix => lat != null && lng != null;
}
