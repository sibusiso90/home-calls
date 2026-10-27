import 'package:fade_call/core/theme.dart';
import 'package:fade_call/data/api_exception.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/state/providers.dart';
import 'package:fade_call/ui/widgets/badges.dart';
import 'package:fade_call/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shows the rating, the rating form (only when `can_rate`), or why rating
/// is locked. No verified job, no rating.
class RatingSection extends ConsumerStatefulWidget {
  const RatingSection({required this.job, super.key});

  final Job job;

  @override
  ConsumerState<RatingSection> createState() => _RatingSectionState();
}

class _RatingSectionState extends ConsumerState<RatingSection> {
  final _comment = TextEditingController();
  int _stars = 0;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(apiProvider)
          .rate(
            widget.job.id,
            stars: _stars,
            comment: _comment.text.trim().isEmpty ? null : _comment.text.trim(),
          );
      ref.refreshJob(widget.job.id);
    } on ApiException catch (e) {
      setState(
        () => _error = e.isVerdictRequired
            ? 'Ratings unlock after a verified job.'
            : e.message,
      );
    } on Object catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    if (job.rating case final r?) {
      return Panel(
        key: const ValueKey('rating-done'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StarRating(stars: r.stars),
            if ((r.comment ?? '').isNotEmpty) ...[
              const SizedBox(height: Gap.sm),
              Text(r.comment!, style: context.text.bodyMedium),
            ],
            const SizedBox(height: Gap.sm),
            Text(
              'Thanks. Your rating counts toward a verified track record.',
              style: context.text.bodySmall,
            ),
          ],
        ),
      );
    }
    if (!job.canRate) {
      return const Callout(
        key: ValueKey('rating-locked'),
        icon: Icons.lock_outline_rounded,
        title: 'Ratings unlock after a verified job',
        text:
            'Once the before and after photos pass every check (or an '
            'operator approves them), you can rate your barber here.',
      );
    }
    return Panel(
      key: const ValueKey('rating-form'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('How was your cut?', style: context.text.titleMedium),
          const SizedBox(height: Gap.sm),
          StarRating(
            stars: _stars,
            size: 34,
            onChanged: (s) => setState(() => _stars = s),
          ),
          const SizedBox(height: Gap.sm),
          TextField(
            controller: _comment,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Anything to add? (optional)',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: Gap.sm),
            Text(
              _error!,
              style: context.text.bodySmall?.copyWith(
                color: context.status.fail,
              ),
            ),
          ],
          const SizedBox(height: Gap.md),
          FilledButton(
            onPressed: _stars == 0 || _sending ? null : _submit,
            child: const Text('Submit rating'),
          ),
        ],
      ),
    );
  }
}
