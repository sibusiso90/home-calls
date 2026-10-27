import 'package:fade_call/core/theme.dart';
import 'package:fade_call/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A network image for short-lived signed media URLs.
///
/// Signed URLs expire after 15 minutes, so this never caches the URL itself.
/// When loading fails, [onExpired] should refetch the parent resource (which
/// hands back fresh URLs) rather than retrying the stale one.
class SignedImage extends ConsumerWidget {
  const SignedImage({
    required this.url,
    super.key,
    this.onExpired,
    this.aspectRatio = 3 / 4,
    this.fit = BoxFit.cover,
    this.radius = 16,
    this.label,
    this.semanticLabel,
  });

  final String? url;
  final VoidCallback? onExpired;
  final double aspectRatio;
  final BoxFit fit;
  final double radius;
  final String? label;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final source = url;
    final Widget image;
    if (source == null || source.isEmpty) {
      image = const _Placeholder(
        icon: Icons.image_not_supported_outlined,
        text: 'No photo yet',
      );
    } else {
      final resolved = ref.watch(apiProvider).mediaUrl(source);
      image = Image.network(
        resolved,
        key: ValueKey(resolved),
        fit: fit,
        semanticLabel: semanticLabel ?? label,
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : ColoredBox(
                color: colors.surfaceContainerHigh,
                child: const Center(
                  child: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              ),
        errorBuilder: (context, error, stack) => _Placeholder(
          icon: Icons.broken_image_outlined,
          text: 'Photo link expired',
          action: onExpired == null
              ? null
              : TextButton.icon(
                  onPressed: onExpired,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Reload'),
                ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            if (label != null)
              Positioned(left: Gap.sm, top: Gap.sm, child: _ImageLabel(label!)),
          ],
        ),
      ),
    );
  }
}

class _ImageLabel extends StatelessWidget {
  const _ImageLabel(this.text);

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
          letterSpacing: 0.3,
        ),
      ),
    ),
  );
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.colors.surfaceContainerHigh,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: context.colors.onSurfaceVariant),
          const SizedBox(height: Gap.xs),
          Text(
            text,
            textAlign: TextAlign.center,
            style: context.text.labelSmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          ?action,
        ],
      ),
    ),
  );
}
