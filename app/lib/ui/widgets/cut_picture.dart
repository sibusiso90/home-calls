import 'package:fade_call/core/theme.dart';
import 'package:fade_call/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A catalog cut's picture: an illustration until a real photo is uploaded.
///
/// The URL is public and doesn't expire, so a failed load just shows an icon.
/// Renders nothing without a URL (a custom cut from a reference photo).
class CutPicture extends ConsumerWidget {
  const CutPicture({
    required this.url,
    required this.name,
    super.key,
    this.size = 64,
    this.radius = 12,
  });

  final String? url;
  final String name;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = url;
    if (source == null) return const SizedBox.shrink();
    final fallback = ColoredBox(
      color: context.colors.surfaceContainerHigh,
      child: Icon(
        Icons.content_cut_rounded,
        color: context.colors.onSurfaceVariant,
        size: size * 0.4,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.square(
        dimension: size,
        child: Image.network(
          ref.watch(apiProvider).mediaUrl(source),
          fit: BoxFit.cover,
          semanticLabel: 'Picture of $name',
          webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : fallback,
          errorBuilder: (context, error, stack) => fallback,
        ),
      ),
    );
  }
}
