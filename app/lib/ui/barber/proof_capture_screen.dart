import 'dart:async';

import 'package:camera/camera.dart';
import 'package:fade_call/core/format.dart';
import 'package:fade_call/core/theme.dart';
import 'package:fade_call/data/api_exception.dart';
import 'package:fade_call/data/device/location_service.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/data/upload_file.dart';
import 'package:fade_call/state/providers.dart';
import 'package:fade_call/ui/widgets/check_row.dart';
import 'package:fade_call/ui/widgets/common.dart';
import 'package:fade_call/ui/widgets/consent_gate.dart';
import 'package:fade_call/ui/widgets/evidence_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _Phase { consent, camera, fallback, review, uploading, result }

/// Live-camera proof of job with a time + GPS overlay. Falls back to a
/// flagged photo upload only when the camera can't be used.
class ProofCaptureScreen extends ConsumerStatefulWidget {
  const ProofCaptureScreen({
    required this.jobId,
    required this.after,
    super.key,
  });

  final String jobId;
  final bool after;

  @override
  ConsumerState<ProofCaptureScreen> createState() => _ProofCaptureScreenState();
}

class _ProofCaptureScreenState extends ConsumerState<ProofCaptureScreen> {
  _Phase _phase = _Phase.consent;

  CameraController? _camera;
  List<CameraDescription> _cameras = const [];
  String? _cameraError;
  bool _shooting = false;

  /// True while a camera is being opened; starts are serialised so fast
  /// switching can't leak a controller.
  bool _cameraStarting = false;

  StreamSubscription<GpsFix>? _gpsSub;
  GpsFix? _fix;
  String? _gpsError;

  Timer? _clock;
  DateTime _now = DateTime.now();

  UploadFile? _photo;
  CaptureMeta? _meta;
  Evidence? _evidence;
  String? _uploadError;

  String get _phaseName => widget.after ? 'after' : 'before';

  @override
  void dispose() {
    _clock?.cancel();
    unawaited(_gpsSub?.cancel());
    unawaited(_camera?.dispose());
    super.dispose();
  }

  // -- Setup ---------------------------------------------------------------

  Future<void> _begin() async {
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    unawaited(_startGps());
    setState(() => _phase = _Phase.camera);
    await _startCamera();
  }

  Future<void> _startGps() async {
    final location = ref.read(locationServiceProvider);
    final problem = await location.ensureReady();
    if (!mounted) return;
    if (problem != null) {
      setState(() => _gpsError = problem);
      return;
    }
    _gpsSub = location.watch().listen(
      (fix) {
        if (!mounted) return;
        setState(() {
          _fix = fix;
          _gpsError = null;
        });
      },
      onError: (Object _) {
        if (!mounted) return;
        // Never keep using a position from before the error.
        setState(() {
          _fix = null;
          _gpsError = 'Could not get a GPS fix.';
        });
      },
    );
  }

  Future<void> _startCamera([CameraDescription? preferred]) async {
    if (_cameraStarting) return;
    _cameraStarting = true;
    setState(() => _cameraError = null);
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
      if (_cameras.isEmpty) throw CameraException('none', 'No camera found');
      final description =
          preferred ??
          _cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
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
      // Belt and braces: nothing else may hold a live controller now.
      final stray = _camera;
      if (stray != null && stray != controller) await stray.dispose();
      setState(() => _camera = controller);
    } on CameraException catch (e) {
      final code = e.code.toLowerCase();
      final denied =
          code.contains('denied') ||
          code.contains('permission') ||
          code.contains('notallowed');
      _cameraFailed(
        denied
            ? 'Camera access was blocked.'
            : 'No camera could be started on this device.',
      );
    } on Object {
      _cameraFailed('The camera could not start.');
    } finally {
      _cameraStarting = false;
      if (mounted) setState(() {});
    }
  }

  void _cameraFailed(String message) {
    if (!mounted) return;
    setState(() {
      _cameraError = message;
      if (_phase == _Phase.camera) _phase = _Phase.fallback;
    });
  }

  Future<void> _switchCamera() async {
    final current = _camera?.description;
    if (_cameraStarting || _cameras.length < 2 || current == null) return;
    final next = _cameras[(_cameras.indexOf(current) + 1) % _cameras.length];
    await _startCamera(next);
  }

  // -- Capture -------------------------------------------------------------

  CaptureMeta _metaAt(DateTime at, CaptureMode mode, GpsFix? fix) =>
      CaptureMeta(
        capturedAt: at,
        mode: mode,
        lat: fix?.lat,
        lng: fix?.lng,
        accuracyM: fix?.accuracyM,
      );

  /// A fix fresh enough to send; if the stream has gone quiet, ask once more
  /// (briefly) rather than send an old position.
  Future<GpsFix?> _fixForShutter(DateTime at) async {
    final fresh = freshFix(_fix, at);
    if (fresh != null || _gpsError != null) return fresh;
    final location = ref.read(locationServiceProvider);
    final fix = await location.currentFix(timeout: const Duration(seconds: 4));
    return freshFix(fix, DateTime.now());
  }

  Future<void> _shoot() async {
    final camera = _camera;
    if (camera == null || _shooting) return;
    setState(() => _shooting = true);
    // Record the time at the shutter, before the (slower) encode.
    final at = DateTime.now();
    try {
      // Never let GPS hold up the shutter: give up after a few seconds and
      // send no position (the backend marks GPS uncertain).
      final fixFuture = _fixForShutter(
        at,
      ).timeout(const Duration(seconds: 5), onTimeout: () => null);
      final file = await camera.takePicture();
      final bytes = await file.readAsBytes();
      final fix = await fixFuture;
      if (!mounted) return;
      setState(() {
        _photo = UploadFile(
          bytes: bytes,
          filename: '$_phaseName.jpg',
          mimeType: 'image/jpeg',
        );
        _meta = _metaAt(at, CaptureMode.live, fix);
        _phase = _Phase.review;
      });
    } on Object {
      if (mounted) showSnack(context, "That photo didn't save. Try again.");
    } finally {
      if (mounted) setState(() => _shooting = false);
    }
  }

  Future<void> _pickFallback() async {
    final file = await ref
        .read(mediaPickerProvider)
        .pickImage(name: _phaseName);
    if (file == null || !mounted) return;
    final now = DateTime.now();
    setState(() {
      _photo = file;
      _meta = _metaAt(now, CaptureMode.uploadFallback, freshFix(_fix, now));
      _phase = _Phase.review;
    });
  }

  void _retake() {
    final wasFallback = _meta?.mode == CaptureMode.uploadFallback;
    setState(() {
      _photo = null;
      _meta = null;
      _uploadError = null;
      _phase = wasFallback || _camera == null ? _Phase.fallback : _Phase.camera;
    });
  }

  Future<void> _upload() async {
    final (photo, meta) = (_photo, _meta);
    if (photo == null || meta == null) return;
    // Capture before the long await: the barber may close the screen while
    // the job is verifying, and the job must still be refreshed.
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() {
      _phase = _Phase.uploading;
      _uploadError = null;
    });
    try {
      final evidence = await container
          .read(apiProvider)
          .uploadProof(
            jobId: widget.jobId,
            after: widget.after,
            photo: photo,
            meta: meta,
          );
      refreshJobIn(container, widget.jobId);
      if (!mounted) return;
      setState(() {
        _evidence = evidence;
        _phase = _Phase.result;
      });
      _clock?.cancel();
      await _gpsSub?.cancel();
      await _camera?.dispose();
      _camera = null;
    } on Object catch (e) {
      if (e case ApiException(isConflict: true, :final message)) {
        // e.g. "Deposit not paid yet" or "This job is already being
        // verified": not a failure of the photo. Refresh the job and go back.
        refreshJobIn(container, widget.jobId);
        if (!mounted) return;
        showSnack(context, message);
        Navigator.of(context).pop(false);
        return;
      }
      if (mounted) {
        setState(() {
          _uploadError = friendlyError(e);
          _phase = _Phase.review;
        });
      }
    }
  }

  // -- UI ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final dark = _phase == _Phase.camera || _phase == _Phase.review;
    return Scaffold(
      backgroundColor: dark ? Colors.black : null,
      appBar: AppBar(
        backgroundColor: dark ? Colors.black : null,
        foregroundColor: dark ? Palette.cream : null,
        title: Text(
          widget.after ? 'After photo' : 'Before photo',
          style: dark ? const TextStyle(color: Palette.cream) : null,
        ),
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(_evidence != null),
        ),
      ),
      body: switch (_phase) {
        _Phase.consent => _consent(),
        _Phase.camera => _cameraView(),
        _Phase.fallback => _fallbackView(),
        _Phase.review => _reviewView(),
        _Phase.uploading => _VerifyingView(after: widget.after),
        _Phase.result => _resultView(),
      },
    );
  }

  Widget _consent() => PageList(
    children: [
      const SizedBox(height: Gap.md),
      ConsentCard(
        topic: ConsentTopic.proofCapture,
        agreeLabel: 'Client agrees. Open the camera',
        onAgree: () => unawaited(_begin()),
      ),
    ],
  );

  Widget _cameraView() {
    final camera = _camera;
    if (_cameraError != null) return _fallbackView();
    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (camera != null && camera.value.isInitialized)
                Center(
                  child: AspectRatio(
                    aspectRatio: camera.value.aspectRatio,
                    child: CameraPreview(camera),
                  ),
                )
              else
                const Center(
                  child: CircularProgressIndicator(color: Palette.cream),
                ),
              Positioned(
                left: Gap.md,
                right: Gap.md,
                bottom: Gap.md,
                child: _Hud(
                  now: _now,
                  fix: freshFix(_fix, _now),
                  gpsError:
                      _gpsError ??
                      (_fix != null && freshFix(_fix, _now) == null
                          ? 'GPS fix is out of date; waiting for a new one'
                          : null),
                  phase: _phaseName,
                ),
              ),
            ],
          ),
        ),
        _ShutterBar(
          shooting: _shooting,
          enabled: camera != null && camera.value.isInitialized,
          onShoot: _shoot,
          onSwitch: _cameras.length > 1 ? _switchCamera : null,
          onFallback: () => setState(() => _phase = _Phase.fallback),
        ),
      ],
    );
  }

  Widget _fallbackView() => PageList(
    children: [
      const SizedBox(height: Gap.md),
      if (_cameraError != null) ...[
        Callout(
          icon: Icons.no_photography_outlined,
          color: context.status.fail,
          background: context.status.failContainer,
          title: 'Camera unavailable',
          text:
              '$_cameraError Allow camera access in your browser settings and '
              'try again, or upload a photo instead.',
        ),
        const SizedBox(height: Gap.md),
      ],
      Callout.warning(
        context,
        'Uploaded photos can\'t prove when and where they were taken, so this '
        'job will be flagged for operator review. Payment waits until an '
        'operator checks it.',
        title: 'Upload fallback: will be flagged for operator review',
      ),
      if (_gpsError != null) ...[
        const SizedBox(height: Gap.md),
        Callout(
          icon: Icons.location_off_outlined,
          text: '$_gpsError The location check will be marked uncertain.',
        ),
      ],
      const SizedBox(height: Gap.lg),
      FilledButton.icon(
        onPressed: _pickFallback,
        icon: const Icon(Icons.upload_rounded),
        label: const Text('Choose a photo to upload'),
      ),
      const SizedBox(height: Gap.sm),
      OutlinedButton.icon(
        onPressed: () {
          setState(() => _phase = _Phase.camera);
          unawaited(_startCamera());
        },
        icon: const Icon(Icons.photo_camera_outlined),
        label: const Text('Try the live camera again'),
      ),
    ],
  );

  Widget _reviewView() {
    final photo = _photo!;
    final meta = _meta!;
    final fallback = meta.mode == CaptureMode.uploadFallback;
    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(photo.bytes, fit: BoxFit.contain),
              Positioned(
                left: Gap.md,
                right: Gap.md,
                bottom: Gap.md,
                child: _Hud(
                  now: meta.capturedAt,
                  fix: meta.hasFix
                      ? (
                          lat: meta.lat!,
                          lng: meta.lng!,
                          accuracyM: meta.accuracyM ?? 0,
                          at: meta.capturedAt,
                        )
                      : null,
                  gpsError: meta.hasFix ? null : 'No GPS fix at capture',
                  phase: _phaseName,
                  frozen: true,
                  flagged: fallback,
                ),
              ),
            ],
          ),
        ),
        ColoredBox(
          color: Colors.black,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Column(
                children: [
                  if (_uploadError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Gap.sm),
                      child: Text(
                        _uploadError!,
                        textAlign: TextAlign.center,
                        style: context.text.bodyMedium?.copyWith(
                          color: const Color(0xFFFFB4A9),
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Palette.cream,
                            side: const BorderSide(color: Palette.cream),
                          ),
                          onPressed: _retake,
                          child: Text(fallback ? 'Choose another' : 'Retake'),
                        ),
                      ),
                      const SizedBox(width: Gap.md),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Palette.brass,
                            foregroundColor: Palette.charcoal,
                          ),
                          onPressed: _upload,
                          child: const Text('Use photo'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _resultView() {
    final e = _evidence!;
    final before = [CheckKind.beforeTimestamp, CheckKind.beforeGps];
    return PageList(
      children: [
        const SizedBox(height: Gap.md),
        if (widget.after)
          EvidenceView(
            evidence: e,
            onExpired: () => ref.invalidate(jobProvider(widget.jobId)),
          )
        else ...[
          VerdictBanner(evidence: e),
          const SizedBox(height: Gap.md),
          Panel(
            child: Column(
              children: [
                for (final k in before)
                  CheckRow(label: k.label, check: e.checks[k]),
              ],
            ),
          ),
        ],
        const SizedBox(height: Gap.lg),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(widget.after ? 'Back to job' : 'Done, start the cut'),
        ),
      ],
    );
  }
}

/// Time + GPS overlay shown on the live preview and the captured photo.
class _Hud extends StatelessWidget {
  const _Hud({
    required this.now,
    required this.fix,
    required this.gpsError,
    required this.phase,
    this.frozen = false,
    this.flagged = false,
  });

  final DateTime now;
  final GpsFix? fix;
  final String? gpsError;
  final String phase;
  final bool frozen;
  final bool flagged;

  @override
  Widget build(BuildContext context) {
    final mono = context.text.bodyMedium?.copyWith(
      color: Palette.cream,
      fontFeatures: const [FontFeature.tabularFigures()],
      fontWeight: FontWeight.w600,
    );
    final f = fix;
    final (gpsIcon, gpsColor, gpsText) = switch ((f, gpsError)) {
      (final GpsFix f, _) => (
        Icons.gps_fixed_rounded,
        f.accuracyM <= 50 ? const Color(0xFF8FE3AE) : const Color(0xFFFFD27A),
        '${f.lat.toStringAsFixed(5)}, ${f.lng.toStringAsFixed(5)}  ±${f.accuracyM.round()} m',
      ),
      (null, final String err) => (
        Icons.gps_off_rounded,
        const Color(0xFFFFB4A9),
        err,
      ),
      _ => (
        Icons.gps_not_fixed_rounded,
        const Color(0xFFFFD27A),
        'Finding GPS…',
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: Gap.sm,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: flagged ? Palette.review : Palette.fail,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Text(
                      flagged
                          ? 'UPLOAD · FLAGGED'
                          : (frozen ? 'CAPTURED' : 'LIVE'),
                      style: context.text.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                Text(
                  '${phase.toUpperCase()} PHOTO',
                  style: context.text.labelMedium?.copyWith(
                    color: Palette.brass,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  size: 16,
                  color: Palette.cream,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '${formatDay(now)}  ${formatClock(now)}',
                    style: mono,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(gpsIcon, size: 16, color: gpsColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    gpsText,
                    style: mono?.copyWith(color: gpsColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ShutterBar extends StatelessWidget {
  const _ShutterBar({
    required this.shooting,
    required this.enabled,
    required this.onShoot,
    required this.onFallback,
    this.onSwitch,
  });

  final bool shooting;
  final bool enabled;
  final VoidCallback onShoot;
  final VoidCallback onFallback;
  final VoidCallback? onSwitch;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                const SizedBox(width: 48),
                Semantics(
                  button: true,
                  label: 'Take photo',
                  child: GestureDetector(
                    onTap: enabled && !shooting ? onShoot : null,
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
                          color: enabled ? Palette.cream : Palette.ink,
                        ),
                        child: shooting
                            ? const Padding(
                                padding: EdgeInsets.all(18),
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: onSwitch == null
                      ? null
                      : IconButton(
                          tooltip: 'Switch camera',
                          onPressed: onSwitch,
                          icon: const Icon(
                            Icons.cameraswitch_rounded,
                            color: Palette.cream,
                          ),
                        ),
                ),
              ],
            ),
            TextButton(
              onPressed: onFallback,
              style: TextButton.styleFrom(foregroundColor: Palette.cream),
              child: const Text('Camera not working? Upload instead'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Shown while the backend runs the checks.
class _VerifyingView extends StatefulWidget {
  const _VerifyingView({required this.after});

  final bool after;

  @override
  State<_VerifyingView> createState() => _VerifyingViewState();
}

class _VerifyingViewState extends State<_VerifyingView> {
  static const _afterSteps = [
    'Checking the time and place',
    'Comparing faces within this job only',
    'Measuring the hair change with SAM 3.1',
    'Matching the result to the ordered cut',
  ];
  static const _beforeSteps = [
    'Uploading the before photo',
    'Checking the time and place',
  ];

  late final Timer _timer;
  int _step = 0;

  List<String> get _steps => widget.after ? _afterSteps : _beforeSteps;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 2600), (_) {
      if (_step < _steps.length - 1) setState(() => _step++);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Gap.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 56,
              child: CircularProgressIndicator(strokeWidth: 4),
            ),
            const SizedBox(height: Gap.lg),
            Text(
              widget.after ? 'Verifying…' : 'Saving the before photo…',
              style: context.text.headlineSmall,
            ),
            const SizedBox(height: Gap.lg),
            for (final (i, s) in _steps.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      i < _step
                          ? Icons.check_circle_rounded
                          : i == _step
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 20,
                      color: i <= _step
                          ? context.colors.primary
                          : context.colors.outline,
                    ),
                    const SizedBox(width: Gap.sm),
                    Text(
                      s,
                      style: context.text.bodyMedium?.copyWith(
                        fontWeight: i == _step ? FontWeight.w700 : null,
                        color: i <= _step
                            ? context.colors.onSurface
                            : context.colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
