import 'dart:async';

import 'package:fade_call/core/theme.dart';
import 'package:fade_call/data/upload_file.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:record/record.dart';

/// Tap to start and stop, or press and hold to record a voice note.
///
/// On web the browser records webm/opus where it can (mp4/aac on Safari);
/// the backend converts whatever it receives.
class VoiceRecorderButton extends StatefulWidget {
  const VoiceRecorderButton({
    required this.onRecorded,
    super.key,
    this.maxDuration = const Duration(minutes: 2),
    this.enabled = true,
    this.idleLabel = 'Tap to record',
  });

  final void Function(UploadFile audio, Duration length) onRecorded;
  final Duration maxDuration;
  final bool enabled;
  final String idleLabel;

  @override
  State<VoiceRecorderButton> createState() => _VoiceRecorderButtonState();
}

class _VoiceRecorderButtonState extends State<VoiceRecorderButton>
    with SingleTickerProviderStateMixin {
  AudioRecorder? _recorder;
  Timer? _ticker;
  StreamSubscription<Amplitude>? _levels;
  final _watch = Stopwatch();
  bool _recording = false;
  bool _busy = false;
  bool _heldDown = false;
  double _level = 0;
  String? _error;
  String _mime = 'audio/webm';
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_levels?.cancel());
    unawaited(_recorder?.dispose());
    _pulse.dispose();
    super.dispose();
  }

  Future<(AudioEncoder, String)> _pickEncoder(AudioRecorder r) async {
    for (final (enc, mime) in const [
      (AudioEncoder.opus, 'audio/webm'),
      (AudioEncoder.aacLc, 'audio/mp4'),
      (AudioEncoder.wav, 'audio/wav'),
    ]) {
      if (await r.isEncoderSupported(enc)) return (enc, mime);
    }
    return (AudioEncoder.wav, 'audio/wav');
  }

  /// Starts recording. With [fromHold], releasing the button while the
  /// permission prompt is up cancels instead of leaving the mic recording.
  Future<void> _start({bool fromHold = false}) async {
    if (_recording || _busy || !widget.enabled) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = _recorder ??= AudioRecorder();
      if (!await r.hasPermission()) throw const _MicDenied();
      if (!mounted) return;
      final (encoder, mime) = await _pickEncoder(r);
      if (!mounted) return;
      _mime = mime;
      await r.start(
        RecordConfig(encoder: encoder, numChannels: 1, echoCancel: true),
        path: '',
      );
      if (!mounted || (fromHold && !_heldDown)) {
        // Disposed, or the finger came off during the prompt: discard.
        await r.cancel();
        return;
      }
      _watch
        ..reset()
        ..start();
      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted) return;
        if (_watch.elapsed >= widget.maxDuration) {
          unawaited(_stop());
        } else {
          setState(() {});
        }
      });
      _levels = r.onAmplitudeChanged(const Duration(milliseconds: 120)).listen((
        a,
      ) {
        if (mounted) {
          setState(() => _level = ((a.current + 50) / 50).clamp(0, 1));
        }
      });
      unawaited(_pulse.repeat(reverse: true));
      setState(() => _recording = true);
    } on _MicDenied {
      _fail(
        'Microphone access was blocked. Allow it in your browser settings and try again.',
      );
    } on Object {
      _fail("We couldn't start recording on this device.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fail(String message) {
    if (mounted) setState(() => _error = message);
  }

  Future<void> _stop() async {
    if (!_recording) return;
    _ticker?.cancel();
    _ticker = null;
    await _levels?.cancel();
    _levels = null;
    _pulse.stop();
    _watch.stop();
    final length = _watch.elapsed;
    if (!mounted) return;
    setState(() {
      _recording = false;
      _busy = true;
    });
    try {
      final path = await _recorder?.stop();
      if (path == null) throw StateError('No audio');
      if (length < const Duration(seconds: 1)) {
        _fail(
          'That was very short. Hold or tap again and speak for a bit longer.',
        );
        return;
      }
      final bytes = await XFile(path).readAsBytes();
      if (!mounted) return;
      final ext = switch (_mime) {
        'audio/mp4' => 'm4a',
        'audio/wav' => 'wav',
        _ => 'webm',
      };
      widget.onRecorded(
        UploadFile(bytes: bytes, filename: 'voice-note.$ext', mimeType: _mime),
        length,
      );
    } on Object {
      _fail("We couldn't save that recording. Please try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _clock(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final active = _recording;
    final color = active ? context.status.fail : context.colors.primary;
    final enabled = widget.enabled && !_busy;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onLongPressStart: enabled
              ? (_) {
                  _heldDown = true;
                  unawaited(_start(fromHold: true));
                }
              : null,
          // Always attached: the release may come while a start is still
          // waiting on the permission prompt (when the button is busy).
          onLongPressEnd: (_) {
            final wasHeld = _heldDown;
            _heldDown = false;
            if (wasHeld && _recording) unawaited(_stop());
          },
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) => DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  if (active)
                    BoxShadow(
                      color: color.withValues(alpha: 0.25),
                      blurRadius: 8 + 22 * _level,
                      spreadRadius: 4 + 14 * _pulse.value,
                    ),
                ],
              ),
              child: child,
            ),
            child: Semantics(
              button: true,
              enabled: enabled,
              label: active ? 'Stop recording' : 'Start recording',
              child: Material(
                color: enabled ? color : context.colors.outline,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: enabled ? (active ? _stop : _start) : null,
                  child: SizedBox.square(
                    dimension: 88,
                    child: _busy
                        ? const Padding(
                            padding: EdgeInsets.all(30),
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            active ? Icons.stop_rounded : Icons.mic_rounded,
                            size: 40,
                            color: Colors.white,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: Gap.sm + 4),
        Text(
          active ? _clock(_watch.elapsed) : widget.idleLabel,
          style: active
              ? context.text.headlineSmall?.copyWith(
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                )
              : context.text.titleSmall,
        ),
        Text(
          active
              ? 'Recording… tap to stop (max ${widget.maxDuration.inMinutes} min)'
              : 'or press and hold while you talk',
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: Gap.sm),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: context.text.bodySmall?.copyWith(color: context.status.fail),
          ),
        ],
      ],
    );
  }
}

class _MicDenied implements Exception {
  const _MicDenied();
}
