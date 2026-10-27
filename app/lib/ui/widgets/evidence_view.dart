import 'package:fade_call/core/format.dart';
import 'package:fade_call/core/theme.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/ui/widgets/ai_attribution.dart';
import 'package:fade_call/ui/widgets/badges.dart';
import 'package:fade_call/ui/widgets/check_row.dart';
import 'package:fade_call/ui/widgets/common.dart';
import 'package:fade_call/ui/widgets/compare_slider.dart';
import 'package:fade_call/ui/widgets/signed_image.dart';
import 'package:flutter/material.dart';

/// Proof-of-job evidence: verdict banner, before/after photos with SAM hair
/// masks (side by side or a drag-to-compare slider, tap for fullscreen), and
/// every check with the model's reason. Shared by barber, client and operator.
class EvidenceView extends StatefulWidget {
  const EvidenceView({
    required this.evidence,
    super.key,
    this.onExpired,
    this.showBanner = true,
    this.compareByDefault = false,
  });

  final Evidence evidence;

  /// Refetches the parent job when a signed URL has expired.
  final VoidCallback? onExpired;
  final bool showBanner;

  /// Start in the compare-slider layout (operator review).
  final bool compareByDefault;

  @override
  State<EvidenceView> createState() => _EvidenceViewState();
}

enum _PhotoMode { mask, photo }

/// Which model produced each check's judgement.
MetaModel? checkModel(CheckKind kind) => switch (kind) {
  CheckKind.samePerson || CheckKind.cutMatch => MetaModel.spark,
  CheckKind.hairChanged => MetaModel.sam,
  _ => null,
};

class _EvidenceViewState extends State<EvidenceView> {
  _PhotoMode _mode = _PhotoMode.mask;
  late bool _compare = widget.compareByDefault;

  void _openFullscreen(int initial) {
    final e = widget.evidence;
    final images = <ViewerImage>[
      if (e.beforeOverlayUrl != null)
        (label: 'Before · hair mask', url: e.beforeOverlayUrl),
      if (e.afterOverlayUrl != null)
        (label: 'After · hair mask', url: e.afterOverlayUrl),
      if (e.beforeUrl != null) (label: 'Before', url: e.beforeUrl),
      if (e.afterUrl != null) (label: 'After', url: e.afterUrl),
    ];
    if (images.isEmpty) return;
    showFullscreenImages(
      context,
      images: images,
      initial: initial.clamp(0, images.length - 1),
      onExpired: widget.onExpired,
    ).ignore();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.evidence;
    final hasMasks =
        !e.isPurged &&
        (e.beforeOverlayUrl != null || e.afterOverlayUrl != null);
    final mode = hasMasks ? _mode : _PhotoMode.photo;
    final masked = mode == _PhotoMode.mask;
    final before = masked ? e.beforeOverlayUrl : e.beforeUrl;
    final after = masked ? e.afterOverlayUrl : e.afterUrl;
    final canCompare = before != null && after != null;
    // Index into the fullscreen list: masks first (when present), then photos.
    final maskCount = [e.beforeOverlayUrl, e.afterOverlayUrl].nonNulls.length;
    final base = masked ? 0 : maskCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showBanner) ...[
          VerdictBanner(evidence: e),
          const SizedBox(height: Gap.md),
        ],
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.sm,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Evidence', style: context.text.titleMedium),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (canCompare && !e.isPurged)
                        IconButton(
                          key: const ValueKey('evidence-layout'),
                          tooltip: _compare ? 'Side by side' : 'Compare slider',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setState(() => _compare = !_compare),
                          icon: Icon(
                            _compare
                                ? Icons.view_column_rounded
                                : Icons.compare_rounded,
                          ),
                        ),
                      if (hasMasks)
                        SegmentedButton<_PhotoMode>(
                          showSelectedIcon: false,
                          style: const ButtonStyle(
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          segments: const [
                            ButtonSegment(
                              value: _PhotoMode.mask,
                              label: Text('Hair mask'),
                            ),
                            ButtonSegment(
                              value: _PhotoMode.photo,
                              label: Text('Photo'),
                            ),
                          ],
                          selected: {mode},
                          onSelectionChanged: (s) =>
                              setState(() => _mode = s.first),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: Gap.md),
              if (e.isPurged)
                Callout(
                  key: const ValueKey('evidence-purged'),
                  icon: Icons.auto_delete_outlined,
                  text:
                      'Photos deleted under the retention policy on '
                      '${formatDay(e.purgedAt)}. The checks and verdict are kept.',
                )
              else if (_compare && canCompare)
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: CompareSlider(
                      key: ValueKey('compare-$mode'),
                      beforeUrl: before,
                      afterUrl: after,
                      onExpired: widget.onExpired,
                      onOpen: () => _openFullscreen(base),
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _openFullscreen(base),
                        child: SignedImage(
                          url: before,
                          label: 'BEFORE',
                          onExpired: widget.onExpired,
                        ),
                      ),
                    ),
                    const SizedBox(width: Gap.sm + 4),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _openFullscreen(base + 1),
                        child: SignedImage(
                          url: after,
                          label: 'AFTER',
                          onExpired: widget.onExpired,
                        ),
                      ),
                    ),
                  ],
                ),
              if (!e.isPurged) ...[
                const SizedBox(height: Gap.sm),
                Wrap(
                  spacing: Gap.sm,
                  runSpacing: Gap.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (masked) ...[
                      const ModelChip(model: MetaModel.sam),
                      Text(
                        'Tinted area is the hair region found by SAM 3.1.',
                        style: context.text.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ] else
                      Text(
                        _compare
                            ? 'Drag the divider. Tap to enlarge.'
                            : 'Tap a photo to enlarge.',
                        style: context.text.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: Gap.md),
              const Divider(),
              for (final kind in CheckKind.values)
                CheckRow(
                  label: kind.label,
                  check: e.checks[kind],
                  model: checkModel(kind),
                ),
              if (e.modelVersions.isNotEmpty) ...[
                const Divider(),
                const SizedBox(height: Gap.sm),
                AiAttribution.fromVersions(
                  e.modelVersions,
                  key: const ValueKey('evidence-attribution'),
                  elapsedMs: e.elapsedMs,
                  prefix: 'Checked by',
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The headline outcome of a proof-of-job check.
class VerdictBanner extends StatelessWidget {
  const VerdictBanner({required this.evidence, super.key});

  final Evidence evidence;

  @override
  Widget build(BuildContext context) {
    final e = evidence;
    final afterIn = e.afterUrl != null;
    final (tone, icon, title, body) = switch (e.verdict) {
      Verdict.pass => (
        Tone.pass,
        Icons.verified_rounded,
        'Verified',
        'Payment released, rating unlocked.',
      ),
      Verdict.needsReview => (
        Tone.review,
        Icons.manage_search_rounded,
        'Sent to operator review',
        'A person will look at the evidence. Payment stays on hold until then.',
      ),
      Verdict.fail => (
        Tone.fail,
        Icons.gpp_bad_rounded,
        'Not verified',
        'The operator did not accept this proof. Payment is held.',
      ),
      null when afterIn => (
        Tone.review,
        Icons.hourglass_top_rounded,
        'Verifying…',
        'Checking the photos. This can take up to 30 seconds.',
      ),
      null => (
        Tone.info,
        Icons.photo_camera_back_rounded,
        'Before photo in',
        'Capture the after photo once the cut is done.',
      ),
    };
    final (fg, bg) = context.toneColors(tone);
    final reasons = e.verdict == Verdict.pass
        ? const <String>[]
        : e.verdictReasons;
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: fg.withValues(alpha: 0.35)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Gap.md + 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: fg, size: 32),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.text.titleLarge?.copyWith(color: fg),
                    ),
                    const SizedBox(height: 2),
                    Text(body, style: context.text.bodyMedium),
                    if (reasons.isNotEmpty) ...[
                      const SizedBox(height: Gap.sm),
                      for (final r in reasons)
                        Text(
                          '• ${CheckKind.describeReason(r)}',
                          style: context.text.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                    if (e.decidedByOperator) ...[
                      const SizedBox(height: Gap.sm),
                      Text(
                        'Decided by a Fade Call operator',
                        style: context.text.labelSmall?.copyWith(color: fg),
                      ),
                      if ((e.operatorReason ?? '').isNotEmpty)
                        Text(
                          '“${e.operatorReason}”',
                          style: context.text.bodySmall?.copyWith(
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
