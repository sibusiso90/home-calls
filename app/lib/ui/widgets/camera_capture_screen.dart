import 'dart:async';

import 'package:camera/camera.dart';
import 'package:fade_call/core/theme.dart';
import 'package:fade_call/data/upload_file.dart';
import 'package:fade_call/state/providers.dart';
import 'package:fade_call/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the live camera full screen and returns the photo, or null if the
/// user closes it. Works on desktop browsers too (getUserMedia), including a
/// phone used as a webcam, where a file input's `capture` hint is ignored.
Future<UploadFile?> captureWithCamera(
  BuildContext context, {
  required String name,
  required String title,
  bool selfie = false,
}) => Navigator.of(context).push<UploadFile>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) =>
        CameraCaptureScreen(name: name, title: title, selfie: selfie),
  ),
);

class CameraCaptureScreen extends ConsumerStatefulWidget {
  const CameraCaptureScreen({
    required this.name,
    required this.title,
    this.selfie = false,
    super.key,
  });

  /// File name stem for the photo, e.g. `selfie`.
  final String name;
  final String title;

  /// Prefer the front camera.
  final bool selfie;

  @override
  ConsumerState<CameraCaptureScreen> createState() =>
      _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends ConsumerState<CameraCaptureScreen> {
  CameraController? _camera;
  List<CameraDescription> _cameras = const [];
  String? _error;
  bool _starting = false;
  bool _shooting = false;
  UploadFile? _photo;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    unawaited(_camera?.dispose());
    super.dispose();
  }

  Future<void> _start([CameraDescription? preferred]) async {
    if (_starting) return;
    _starting = true;
    setState(() => _error = null);
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
      if (_cameras.isEmpty) throw CameraException('none', 'No camera found');
      final want = widget.selfie
          ? CameraLensDirection.front
          : CameraLensDirection.back;
      final description =
          preferred ??
          _cameras.firstWhere(
            (c) => c.lensDirection == want,
            orElse: () => _cameras.first,
          );
      final old = _camera;
      _camera = null;
      await old?.dispose();
      final controller = CameraController(
        description,
        ResolutionPreset.high,
        enableAudio: false,
      );
      try {
        await controller.initialize();
      } on Object {
        await controller.dispose();
        rethrow;
      }
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _camera = controller);
    } on CameraException catch (e) {
      final code = e.code.toLowerCase();
      final denied =
          code.contains('denied') ||
          code.contains('permission') ||
          code.contains('notallowed');
      _failed(
        denied
            ? 'Camera access was blocked. Allow it in your browser settings.'
            : 'No camera could be started on this device.',
      );
    } on Object {
      _failed('The camera could not start.');
    } finally {
      _starting = false;
      if (mounted) setState(() {});
    }
  }

  void _failed(String message) {
    if (mounted) setState(() => _error = message);
  }

  Future<void> _switch() async {
    final current = _camera?.description;
    if (_starting || _cameras.length < 2 || current == null) return;
    await _start(_cameras[(_cameras.indexOf(current) + 1) % _cameras.length]);
  }

  Future<void> _shoot() async {
    final camera = _camera;
    if (camera == null || _shooting) return;
    setState(() => _shooting = true);
    try {
      final file = await camera.takePicture();
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(
        () => _photo = UploadFile(
          bytes: bytes,
          filename: '${widget.name}.jpg',
          mimeType: 'image/jpeg',
        ),
      );
    } on Object {
      if (mounted) showSnack(context, "That photo didn't save. Try again.");
    } finally {
      if (mounted) setState(() => _shooting = false);
    }
  }

  Future<void> _pickFile() async {
    final file = await ref
        .read(mediaPickerProvider)
        .pickImage(name: widget.name);
    if (file != null && mounted) Navigator.of(context).pop(file);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Palette.cream,
      title: Text(widget.title, style: const TextStyle(color: Palette.cream)),
      leading: IconButton(
        tooltip: 'Close',
        icon: const Icon(Icons.close_rounded),
        onPressed: () => Navigator.of(context).pop(),
      ),
    ),
    body: switch ((_photo, _error)) {
      (final UploadFile photo, _) => _review(photo),
      (null, final String error) => _unavailable(error),
      _ => _preview(),
    },
  );

  Widget _preview() {
    final camera = _camera;
    final ready = camera != null && camera.value.isInitialized;
    return Column(
      children: [
        Expanded(
          child: ready
              ? Center(
                  child: AspectRatio(
                    aspectRatio: camera.value.aspectRatio,
                    child: CameraPreview(camera),
                  ),
                )
              : const Center(
                  child: CircularProgressIndicator(color: Palette.cream),
                ),
        ),
        _Controls(
          children: [
            const SizedBox(width: 48),
            Semantics(
              button: true,
              label: 'Take photo',
              child: GestureDetector(
                onTap: ready && !_shooting ? _shoot : null,
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Palette.cream, width: 4),
                  ),
                  padding: const EdgeInsets.all(5),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ready ? Palette.cream : Palette.ink,
                    ),
                    child: _shooting
                        ? const Padding(
                            padding: EdgeInsets.all(18),
                            child: CircularProgressIndicator(strokeWidth: 3),
                          )
                        : null,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 48,
              child: _cameras.length > 1
                  ? IconButton(
                      tooltip: 'Switch camera',
                      onPressed: _switch,
                      icon: const Icon(
                        Icons.cameraswitch_rounded,
                        color: Palette.cream,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _review(UploadFile photo) => Column(
    children: [
      Expanded(child: Image.memory(photo.bytes, fit: BoxFit.contain)),
      _Controls(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Palette.cream,
                side: const BorderSide(color: Palette.cream),
              ),
              onPressed: () => setState(() => _photo = null),
              child: const Text('Retake'),
            ),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Palette.brass,
                foregroundColor: Palette.charcoal,
              ),
              onPressed: () => Navigator.of(context).pop(photo),
              child: const Text('Use photo'),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _unavailable(String error) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Gap.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              size: 48,
              color: Palette.cream,
            ),
            const SizedBox(height: Gap.md),
            Text(
              error,
              textAlign: TextAlign.center,
              style: context.text.bodyLarge?.copyWith(color: Palette.cream),
            ),
            const SizedBox(height: Gap.lg),
            FilledButton.icon(
              onPressed: () => unawaited(_start()),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Try the camera again'),
            ),
            const SizedBox(height: Gap.sm),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Palette.cream,
                side: const BorderSide(color: Palette.cream),
              ),
              onPressed: _pickFile,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Choose a photo instead'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Controls extends StatelessWidget {
  const _Controls({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: children,
        ),
      ),
    ),
  );
}
