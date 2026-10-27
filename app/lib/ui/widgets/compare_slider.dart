import 'package:fade_call/core/theme.dart';
import 'package:fade_call/ui/widgets/signed_image.dart';
import 'package:flutter/material.dart';

/// Before/after compare: the before image is revealed left of a draggable
/// divider, the after image right of it. Tap (without dragging) to open
/// fullscreen.
class CompareSlider extends StatefulWidget {
  const CompareSlider({
    required this.beforeUrl,
    required this.afterUrl,
    super.key,
    this.onExpired,
    this.onOpen,
    this.aspectRatio = 3 / 4,
    this.initial = 0.5,
  });

  final String? beforeUrl;
  final String? afterUrl;
  final VoidCallback? onExpired;
  final VoidCallback? onOpen;
  final double aspectRatio;
  final double initial;

  @override
  State<CompareSlider> createState() => CompareSliderState();
}

class CompareSliderState extends State<CompareSlider> {
  late double _split = widget.initial;

  /// Current divider position, 0 (all after) to 1 (all before).
  double get split => _split;

  void _set(double v) => setState(() => _split = v.clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: widget.aspectRatio,
    child: LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final x = _split * w;
        return Semantics(
          slider: true,
          label: 'Before and after compare',
          value: '${(_split * 100).round()}% before',
          increasedValue:
              '${((_split + 0.1).clamp(0, 1) * 100).round()}% before',
          decreasedValue:
              '${((_split - 0.1).clamp(0, 1) * 100).round()}% before',
          onIncrease: () => _set(_split + 0.1),
          onDecrease: () => _set(_split - 0.1),
          child: GestureDetector(
            key: const ValueKey('compare-slider'),
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) => _set(d.localPosition.dx / w),
            onTap: widget.onOpen,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  SignedImage(
                    url: widget.afterUrl,
                    aspectRatio: null,
                    radius: 0,
                    onExpired: widget.onExpired,
                  ),
                  ClipRect(
                    clipper: _LeftOf(_split),
                    child: SignedImage(
                      url: widget.beforeUrl,
                      aspectRatio: null,
                      radius: 0,
                      onExpired: widget.onExpired,
                    ),
                  ),
                  const Positioned(
                    left: Gap.sm,
                    top: Gap.sm,
                    child: _Tag('BEFORE'),
                  ),
                  const Positioned(
                    right: Gap.sm,
                    top: Gap.sm,
                    child: _Tag('AFTER'),
                  ),
                  Positioned(
                    left: x - 1.5,
                    top: 0,
                    bottom: 0,
                    child: const SizedBox(
                      width: 3,
                      child: ColoredBox(color: Palette.cream),
                    ),
                  ),
                  Positioned(
                    left: x - 20,
                    top: 0,
                    bottom: 0,
                    child: const Center(child: _Handle()),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _LeftOf extends CustomClipper<Rect> {
  const _LeftOf(this.fraction);

  final double fraction;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_LeftOf old) => old.fraction != fraction;
}

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Palette.cream,
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 8),
      ],
    ),
    child: const SizedBox.square(
      dimension: 40,
      child: Icon(Icons.compare_arrows_rounded, color: Palette.forest),
    ),
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Palette.charcoal.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Text(
        text,
        style: context.text.labelSmall?.copyWith(
          color: Palette.cream,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

/// One image in the fullscreen viewer.
typedef ViewerImage = ({String label, String? url});

/// Fullscreen, zoomable viewer; swipe between images.
Future<void> showFullscreenImages(
  BuildContext context, {
  required List<ViewerImage> images,
  int initial = 0,
  VoidCallback? onExpired,
}) => Navigator.of(context, rootNavigator: true).push(
  PageRouteBuilder<void>(
    opaque: false,
    barrierColor: Colors.black,
    pageBuilder: (context, _, _) => FullscreenImages(
      images: images,
      initial: initial,
      onExpired: onExpired,
    ),
    transitionsBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  ),
);

class FullscreenImages extends StatefulWidget {
  const FullscreenImages({
    required this.images,
    super.key,
    this.initial = 0,
    this.onExpired,
  });

  final List<ViewerImage> images;
  final int initial;
  final VoidCallback? onExpired;

  @override
  State<FullscreenImages> createState() => _FullscreenImagesState();
}

class _FullscreenImagesState extends State<FullscreenImages> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: SafeArea(
      child: Stack(
        children: [
          PageView(
            controller: _pages,
            onPageChanged: (i) => setState(() => _index = i),
            children: [
              for (final img in widget.images)
                InteractiveViewer(
                  maxScale: 5,
                  child: Center(
                    child: SignedImage(
                      url: img.url,
                      aspectRatio: null,
                      radius: 0,
                      fit: BoxFit.contain,
                      onExpired: widget.onExpired,
                    ),
                  ),
                ),
            ],
          ),
          Positioned(
            left: Gap.md,
            top: Gap.sm,
            child: _Tag(widget.images[_index].label.toUpperCase()),
          ),
          if (widget.images.length > 1)
            Positioned(
              bottom: Gap.md,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  '${_index + 1} / ${widget.images.length} · swipe, pinch to zoom',
                  style: context.text.labelMedium?.copyWith(
                    color: Palette.cream.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ),
          Positioned(
            right: Gap.sm,
            top: 0,
            child: IconButton(
              tooltip: 'Close',
              color: Palette.cream,
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ],
      ),
    ),
  );
}
