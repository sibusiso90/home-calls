import 'package:fade_call/core/theme.dart';
import 'package:fade_call/data/api_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Centres content and caps its width so phone layouts read well on desktop.
class ResponsiveCenter extends StatelessWidget {
  const ResponsiveCenter({
    required this.child,
    super.key,
    this.maxWidth = 720,
    this.padding = const EdgeInsets.symmetric(horizontal: Gap.md),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: SizedBox(
        width: double.infinity,
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

/// A scrolling page body with a capped width.
class PageList extends StatelessWidget {
  const PageList({
    required this.children,
    super.key,
    this.maxWidth = 720,
    this.onRefresh,
  });

  final List<Widget> children;
  final double maxWidth;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      padding: const EdgeInsets.fromLTRB(0, Gap.sm, 0, Gap.xxl),
      children: [
        for (final child in children)
          ResponsiveCenter(maxWidth: maxWidth, child: child),
      ],
    );
    return onRefresh == null
        ? list
        : RefreshIndicator(onRefresh: onRefresh!, child: list);
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Gap.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 32,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          if (message != null) ...[
            const SizedBox(height: Gap.md),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class MessageView extends StatelessWidget {
  const MessageView({
    required this.icon,
    required this.title,
    super.key,
    this.message,
    this.action,
    this.tone,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final color = tone ?? context.colors.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(Gap.md),
                  child: Icon(icon, size: 32, color: color),
                ),
              ),
              const SizedBox(height: Gap.md),
              Text(
                title,
                textAlign: TextAlign.center,
                style: context.text.titleLarge,
              ),
              if (message != null) ...[
                const SizedBox(height: Gap.sm),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: context.text.bodyMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
              if (action != null) ...[const SizedBox(height: Gap.lg), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({required this.error, super.key, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => MessageView(
    icon: Icons.cloud_off_rounded,
    tone: context.status.fail,
    title: "That didn't load",
    message: friendlyError(error),
    action: onRetry == null
        ? null
        : OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
  );
}

/// Renders an [AsyncValue] with consistent loading, error and empty states.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    required this.value,
    required this.builder,
    super.key,
    this.onRetry,
    this.loadingMessage,
    this.isEmpty,
    this.empty,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;
  final String? loadingMessage;
  final bool Function(T data)? isEmpty;
  final Widget? empty;

  @override
  Widget build(BuildContext context) => value.when(
    // Keep showing data while a refresh is in flight.
    skipLoadingOnReload: true,
    data: (data) => (isEmpty?.call(data) ?? false)
        ? (empty ?? const SizedBox.shrink())
        : builder(data),
    error: (error, _) => ErrorView(error: error, onRetry: onRetry),
    loading: () => LoadingView(message: loadingMessage),
  );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    super.key,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.only(top: Gap.lg, bottom: Gap.sm),
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: context.text.labelMedium?.copyWith(
                  letterSpacing: 1.2,
                  color: context.colors.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// A white rounded card with standard padding.
class Panel extends StatelessWidget {
  const Panel({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(Gap.md),
    this.color,
    this.borderColor,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    child: Card(
      color: color,
      clipBehavior: Clip.antiAlias,
      shape: borderColor == null
          ? null
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: borderColor!),
            ),
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

/// Label above a value, used in stat rows.
class Stat extends StatelessWidget {
  const Stat({required this.label, required this.value, super.key, this.icon});

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: context.colors.secondary),
            const SizedBox(width: Gap.xs),
          ],
          Text(value, style: context.text.titleLarge?.copyWith(fontSize: 20)),
        ],
      ),
      Text(
        label,
        style: context.text.labelSmall?.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      ),
    ],
  );
}

/// An icon + text detail line.
class DetailLine extends StatelessWidget {
  const DetailLine({required this.icon, required this.text, super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: context.colors.onSurfaceVariant),
        const SizedBox(width: Gap.sm),
        Expanded(child: Text(text, style: context.text.bodyMedium)),
      ],
    ),
  );
}

/// A tinted note box: info, warning or error.
class Callout extends StatelessWidget {
  const Callout({
    required this.text,
    super.key,
    this.icon = Icons.info_outline_rounded,
    this.color,
    this.background,
    this.title,
  });

  factory Callout.warning(BuildContext context, String text, {String? title}) =>
      Callout(
        text: text,
        title: title,
        icon: Icons.warning_amber_rounded,
        color: context.status.review,
        background: context.status.reviewContainer,
      );

  final String text;
  final String? title;
  final IconData icon;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? context.colors.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color:
            background ??
            context.colors.primaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Gap.md - 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: fg),
            const SizedBox(width: Gap.sm + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    Text(
                      title!,
                      style: context.text.titleSmall?.copyWith(color: fg),
                    ),
                  Text(text, style: context.text.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Asks for a free-text reason; returns null if cancelled.
Future<String?> askReason(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String hint = 'Reason',
  bool destructive = false,
}) => showDialog<String>(
  context: context,
  builder: (context) => _ReasonDialog(
    title: title,
    confirmLabel: confirmLabel,
    hint: hint,
    destructive: destructive,
  ),
);

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.confirmLabel,
    required this.hint,
    required this.destructive,
  });

  final String title;
  final String confirmLabel;
  final String hint;
  final bool destructive;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 420,
      child: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 2,
        maxLines: 4,
        decoration: InputDecoration(hintText: widget.hint),
        onChanged: (_) => setState(() {}),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        style: widget.destructive
            ? FilledButton.styleFrom(backgroundColor: context.status.fail)
            : null,
        onPressed: _controller.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _controller.text.trim()),
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}
