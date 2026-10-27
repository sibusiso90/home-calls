import 'package:fade_call/data/upload_file.dart';
import 'package:image_picker/image_picker.dart';

/// Picks a photo from the gallery or the device camera. Used for portfolio,
/// quote photos and the flagged proof-of-job upload fallback only.
final class MediaPicker {
  const MediaPicker();

  static final _picker = ImagePicker();

  Future<UploadFile?> pickImage({
    required String name,
    bool camera = false,
  }) async {
    final XFile? file;
    try {
      file = await _picker.pickImage(
        source: camera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 88,
      );
    } on Object {
      // A cancelled or blocked browser file picker is not an error to show.
      return null;
    }
    return file == null ? null : toUpload(file, name: name);
  }
}

Future<UploadFile> toUpload(XFile file, {required String name}) async {
  final bytes = await file.readAsBytes();
  final mime = file.mimeType ?? _guessMime(file.name);
  final ext = switch (mime) {
    'image/png' => 'png',
    'image/webp' => 'webp',
    'audio/webm' || 'audio/webm; codecs=opus' => 'webm',
    _ when mime.startsWith('audio/') => mime.split('/').last.split(';').first,
    _ => 'jpg',
  };
  return UploadFile(bytes: bytes, filename: '$name.$ext', mimeType: mime);
}

String _guessMime(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.heic')) return 'image/heic';
  return 'image/jpeg';
}
