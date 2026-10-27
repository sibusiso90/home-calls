import 'dart:async';

import 'package:fade_call/core/theme.dart';
import 'package:fade_call/data/api_exception.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/data/upload_file.dart';
import 'package:fade_call/router.dart';
import 'package:fade_call/state/providers.dart';
import 'package:fade_call/state/quote_state.dart';
import 'package:fade_call/ui/widgets/ai_attribution.dart';
import 'package:fade_call/ui/widgets/common.dart';
import 'package:fade_call/ui/widgets/consent_gate.dart';
import 'package:fade_call/ui/widgets/fade_app_bar.dart';
import 'package:fade_call/ui/widgets/signed_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class QuoteScreen extends ConsumerWidget {
  const QuoteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(quoteControllerProvider);
    final controller = ref.read(quoteControllerProvider.notifier);
    final Widget body = switch (draft.result) {
      AsyncData(:final value) => _QuoteResult(quote: value),
      AsyncError(:final error) => _QuoteError(
        error: error,
        onRetry: () => unawaited(controller.submit()),
        onEdit: controller.editInputs,
      ),
      AsyncLoading() => _QuoteProgress(startedAt: draft.startedAt),
      null => const _QuoteForm(),
    };
    return Scaffold(
      appBar: FadeAppBar(
        title: 'Get a quote',
        actions: [
          if (draft.quote != null)
            IconButton(
              tooltip: 'New quote',
              onPressed: controller.reset,
              icon: const Icon(Icons.restart_alt_rounded),
            ),
        ],
      ),
      body: PageList(
        children: [
          const SizedBox(height: Gap.sm),
          ConsentGate(topic: ConsentTopic.quotePhotos, child: body),
        ],
      ),
    );
  }
}

class _QuoteForm extends ConsumerWidget {
  const _QuoteForm();

  Future<void> _pick(
    WidgetRef ref, {
    required bool selfie,
    required bool camera,
  }) async {
    final file = await ref
        .read(mediaPickerProvider)
        .pickImage(name: selfie ? 'selfie' : 'reference', camera: camera);
    if (file == null) return;
    final c = ref.read(quoteControllerProvider.notifier);
    selfie ? c.setSelfie(file) : c.setReference(file);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(quoteControllerProvider);
    final areas = ref.watch(areasProvider);
    final controller = ref.read(quoteControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('What are we cutting?', style: context.text.headlineMedium),
        const SizedBox(height: Gap.xs),
        Text(
          'Send a selfie and a photo of the cut you want. We name the cut, '
          'estimate the time and price it with travel included.',
          style: context.text.bodyMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
        const SectionHeader(title: 'Where are you?'),
        switch (areas) {
          AsyncData(:final value) => DropdownButtonFormField<String>(
            key: const ValueKey('quote-area'),
            initialValue: draft.areaId,
            decoration: const InputDecoration(
              labelText: 'Your suburb',
              prefixIcon: Icon(Icons.place_outlined),
            ),
            items: [
              for (final a in value)
                DropdownMenuItem(value: a.id, child: Text(a.name)),
            ],
            onChanged: controller.setArea,
          ),
          AsyncError(:final error) => ErrorView(
            error: error,
            onRetry: () => ref.invalidate(areasProvider),
          ),
          _ => const LinearProgressIndicator(),
        },
        const SectionHeader(title: 'Your photos'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _QuotePhotoTile(
                title: 'Selfie',
                hint: 'Face the camera, hair visible',
                icon: Icons.face_retouching_natural_rounded,
                file: draft.selfie,
                onCamera: () => _pick(ref, selfie: true, camera: true),
                onGallery: () => _pick(ref, selfie: true, camera: false),
              ),
            ),
            const SizedBox(width: Gap.sm + 4),
            Expanded(
              child: _QuotePhotoTile(
                title: 'Reference',
                hint: 'The cut you want',
                icon: Icons.style_rounded,
                file: draft.reference,
                onCamera: () => _pick(ref, selfie: false, camera: true),
                onGallery: () => _pick(ref, selfie: false, camera: false),
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.lg),
        FilledButton.icon(
          key: const ValueKey('quote-submit'),
          onPressed: draft.ready ? () => unawaited(controller.submit()) : null,
          icon: const Icon(Icons.auto_awesome_rounded),
          label: const Text('Get my quote'),
        ),
        const SizedBox(height: Gap.sm),
        Text(
          'Usually ready in under 30 seconds.',
          textAlign: TextAlign.center,
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _QuotePhotoTile extends StatelessWidget {
  const _QuotePhotoTile({
    required this.title,
    required this.hint,
    required this.icon,
    required this.file,
    required this.onCamera,
    required this.onGallery,
  });

  final String title;
  final String hint;
  final IconData icon;
  final UploadFile? file;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) => Panel(
    padding: const EdgeInsets.all(Gap.sm + 2),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 3 / 4,
            child: file == null
                ? ColoredBox(
                    color: context.colors.surfaceContainer,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 36, color: context.colors.primary),
                        const SizedBox(height: Gap.sm),
                        Text(title, style: context.text.titleSmall),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Gap.sm,
                          ),
                          child: Text(
                            hint,
                            textAlign: TextAlign.center,
                            style: context.text.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  )
                : Image.memory(file!.bytes, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: Gap.sm),
        Row(
          children: [
            Expanded(
              child: IconButton.filledTonal(
                tooltip: 'Take $title photo',
                onPressed: onCamera,
                icon: const Icon(Icons.photo_camera_outlined),
              ),
            ),
            Expanded(
              child: IconButton.filledTonal(
                tooltip: 'Choose $title photo',
                onPressed: onGallery,
                icon: const Icon(Icons.photo_library_outlined),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _QuoteProgress extends StatefulWidget {
  const _QuoteProgress({required this.startedAt});

  final DateTime? startedAt;

  @override
  State<_QuoteProgress> createState() => _QuoteProgressState();
}

class _QuoteProgressState extends State<_QuoteProgress> {
  late final Timer _timer;

  static const _messages = [
    'Finding the hair in both photos with SAM 3.1…',
    'Naming the cut in your reference photo…',
    'Checking your hair can take this style…',
    'Estimating time and pricing your home call…',
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(
      widget.startedAt ?? DateTime.now(),
    );
    final seconds = elapsed.inMilliseconds / 1000;
    final message = _messages[(seconds ~/ 6).clamp(0, _messages.length - 1)];
    return Panel(
      padding: const EdgeInsets.all(Gap.lg),
      child: Column(
        children: [
          const SizedBox(height: Gap.md),
          Text('Working on your quote', style: context.text.headlineSmall),
          const SizedBox(height: Gap.lg),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: (seconds / 30).clamp(0.02, 0.95),
              minHeight: 10,
            ),
          ),
          const SizedBox(height: Gap.md),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              message,
              key: ValueKey(message),
              textAlign: TextAlign.center,
              style: context.text.bodyMedium,
            ),
          ),
          const SizedBox(height: Gap.sm),
          Text(
            '${seconds.toStringAsFixed(0)} s · can take up to 30 s',
            style: context.text.labelMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Gap.md),
        ],
      ),
    );
  }
}

class _QuoteError extends StatelessWidget {
  const _QuoteError({
    required this.error,
    required this.onRetry,
    required this.onEdit,
  });

  final Object error;
  final VoidCallback onRetry;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Callout(
        icon: Icons.error_outline_rounded,
        color: context.status.fail,
        background: context.status.failContainer,
        title: "We couldn't quote that",
        text: friendlyError(error),
      ),
      const SizedBox(height: Gap.md),
      FilledButton(onPressed: onRetry, child: const Text('Try again')),
      const SizedBox(height: Gap.sm),
      OutlinedButton(onPressed: onEdit, child: const Text('Change photos')),
    ],
  );
}

class _QuoteResult extends ConsumerStatefulWidget {
  const _QuoteResult({required this.quote});

  final Quote quote;

  @override
  ConsumerState<_QuoteResult> createState() => _QuoteResultState();
}

class _QuoteResultState extends ConsumerState<_QuoteResult> {
  bool _masks = true;

  void _refresh() =>
      ref.read(quoteControllerProvider.notifier).refreshUrls().ignore();

  @override
  Widget build(BuildContext context) {
    final q = widget.quote;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Palette.forest, Palette.forestDeep],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(Gap.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'YOUR CUT',
                  style: context.text.labelMedium?.copyWith(
                    color: Palette.brass,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: Gap.xs),
                Text(
                  q.cutName,
                  key: const ValueKey('quote-cut-name'),
                  style: context.text.headlineMedium?.copyWith(
                    color: Palette.cream,
                  ),
                ),
                const SizedBox(height: Gap.md),
                Wrap(
                  spacing: Gap.sm,
                  runSpacing: Gap.sm,
                  children: [
                    _DarkChip(
                      icon: Icons.timer_outlined,
                      text: '${q.minutes} min',
                    ),
                  ],
                ),
                const SizedBox(height: Gap.md),
                AiAttribution.fromVersions(
                  q.modelVersions,
                  key: const ValueKey('quote-attribution'),
                  elapsedMs: q.elapsedMs,
                  dark: true,
                  prefix: 'Named and timed by',
                  fallback: const [MetaModel.spark, MetaModel.sam],
                ),
              ],
            ),
          ),
        ),
        if (q.fitIssues.isNotEmpty) ...[
          const SectionHeader(title: 'Fit check'),
          for (final issue in q.fitIssues) ...[
            Callout.warning(context, issue),
            const SizedBox(height: Gap.sm),
          ],
        ],
        const SectionHeader(
          title: 'Why this cut',
          trailing: ModelChip(model: MetaModel.spark),
        ),
        Panel(child: Text(q.reasons, style: context.text.bodyMedium)),
        SectionHeader(
          title: 'Hair found in your photos',
          trailing: TextButton(
            onPressed: () => setState(() => _masks = !_masks),
            child: Text(_masks ? 'Show photos' : 'Show hair mask'),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: SignedImage(
                url: _masks ? q.selfieOverlayUrl : q.selfieUrl,
                label: 'YOU',
                onExpired: _refresh,
              ),
            ),
            const SizedBox(width: Gap.sm + 4),
            Expanded(
              child: SignedImage(
                url: _masks ? q.referenceOverlayUrl : q.referenceUrl,
                label: 'REFERENCE',
                onExpired: _refresh,
              ),
            ),
          ],
        ),
        if (_masks)
          Padding(
            padding: const EdgeInsets.only(top: Gap.sm),
            child: Wrap(
              spacing: Gap.sm,
              runSpacing: Gap.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const ModelChip(model: MetaModel.sam),
                Text(
                  'Tinted area is the hair region found by SAM 3.1.',
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: Gap.lg),
        FilledButton.icon(
          onPressed: () => context.go(Routes.matches(q.id)),
          icon: const Icon(Icons.groups_rounded),
          label: const Text('See barbers near you'),
        ),
        const SizedBox(height: Gap.sm),
        OutlinedButton(
          onPressed: ref.read(quoteControllerProvider.notifier).reset,
          child: const Text('Start a new quote'),
        ),
      ],
    );
  }
}

class _DarkChip extends StatelessWidget {
  const _DarkChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Palette.cream.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Palette.brass),
          const SizedBox(width: 6),
          Text(
            text,
            style: context.text.labelLarge?.copyWith(color: Palette.cream),
          ),
        ],
      ),
    ),
  );
}
