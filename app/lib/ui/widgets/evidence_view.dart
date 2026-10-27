import 'package:fade_call/core/format.dart';
import 'package:fade_call/core/theme.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/ui/widgets/badges.dart';
import 'package:fade_call/ui/widgets/check_row.dart';
import 'package:fade_call/ui/widgets/common.dart';
import 'package:fade_call/ui/widgets/signed_image.dart';
import 'package:flutter/material.dart';

/// Proof-of-job evidence: verdict banner, before/after photos with SAM hair
/// masks, and every check with the model's reason. Shared by barber, client
/// and operator views.
class EvidenceView extends StatefulWidget {
  const EvidenceView({
    required this.evidence,
    super.key,
    this.onExpired,
    this.showBanner = true,
  });

  final Evidence evidence;

  /// Refetches the parent job when a signed URL has expired.
  final VoidCallback? onExpired;
  final bool showBanner;

  @override
  State<EvidenceView> createState() => _EvidenceViewState();
}

enum _PhotoMode { mask, photo }

class _EvidenceViewState extends State<EvidenceView> {
  _PhotoMode _mode = _PhotoMode.mask;

  @override
  Widget build(BuildContext context) {
    final e = widget.evidence;
    final hasMasks =
        !e.isPurged &&
        (e.beforeOverlayUrl != null || e.afterOverlayUrl != null);
    final mode = hasMasks ? _mode : _PhotoMode.photo;
    final before = mode == _PhotoMode.mask ? e.beforeOverlayUrl : e.beforeUrl;
    final after = mode == _PhotoMode.mask ? e.afterOverlayUrl : e.afterUrl;

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
              Row(
                children: [
                  Expanded(
                    child: Text('Evidence', style: context.text.titleMedium),
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
              const SizedBox(height: Gap.md),
              if (e.isPurged)
                Callout(
                  key: const ValueKey('evidence-purged'),
                  icon: Icons.auto_delete_outlined,
                  text:
                      'Photos deleted under the retention policy on '
                      '${formatDay(e.purgedAt)}. The checks and verdict are kept.',
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: SignedImage(
                        url: before,
                        label: 'BEFORE',
                        onExpired: widget.onExpired,
                      ),
                    ),
                    const SizedBox(width: Gap.sm + 4),
                    Expanded(
                      child: SignedImage(
                        url: after,
                        label: 'AFTER',
                        onExpired: widget.onExpired,
                      ),
                    ),
                  ],
                ),
              if (mode == _PhotoMode.mask && !e.isPurged) ...[
                const SizedBox(height: Gap.sm),
                Text(
                  'Tinted area is the hair region found by SAM 3.1.',
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: Gap.md),
              const Divider(),
              for (final kind in CheckKind.values)
                CheckRow(label: kind.label, check: e.checks[kind]),
              if (e.modelVersions.isNotEmpty) ...[
                const Divider(),
                const SizedBox(height: Gap.sm),
                Text(
                  'Checked by ${e.modelVersions.values.toSet().join(' · ')}',
                  style: context.text.labelSmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
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
