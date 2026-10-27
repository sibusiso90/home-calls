import 'package:fade_call/core/format.dart';
import 'package:fade_call/core/theme.dart';
import 'package:fade_call/data/api_exception.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/data/upload_file.dart';
import 'package:fade_call/state/providers.dart';
import 'package:fade_call/ui/widgets/ai_attribution.dart';
import 'package:fade_call/ui/widgets/badges.dart';
import 'package:fade_call/ui/widgets/common.dart';
import 'package:fade_call/ui/widgets/voice_recorder_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Report a problem": a voice note (and optional text) becomes a case
/// summary for the operator.
class DisputeSection extends ConsumerWidget {
  const DisputeSection({required this.job, super.key});

  final Job job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (job.dispute case final d?) return DisputeSummaryCard(dispute: d);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Not happy with the cut or the visit? Tell us in a voice note '
            'and an operator will review it with the photos.',
            style: context.text.bodyMedium,
          ),
          const SizedBox(height: Gap.md),
          OutlinedButton.icon(
            onPressed: () => showModalBottomSheet<void>(
              useRootNavigator: true,
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              constraints: const BoxConstraints(maxWidth: 640),
              builder: (_) => _DisputeSheet(jobId: job.id),
            ),
            icon: const Icon(Icons.mic_none_rounded),
            label: const Text('Report a problem'),
          ),
        ],
      ),
    );
  }
}

class DisputeSummaryCard extends StatelessWidget {
  const DisputeSummaryCard({required this.dispute, super.key});

  final Dispute dispute;

  @override
  Widget build(BuildContext context) {
    final d = dispute;
    return Panel(
      borderColor: context.status.review,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Your report', style: context.text.titleMedium),
              ),
              StatusPill(
                label: d.isOpen ? 'With operator' : 'Resolved',
                tone: d.isOpen ? Tone.review : Tone.pass,
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Text(d.summary, style: context.text.bodyMedium),
          const SizedBox(height: Gap.sm),
          AiAttribution.fromVersions(
            d.modelVersions,
            elapsedMs: d.elapsedMs,
            prefix: 'Summarised by',
            fallback: const [MetaModel.transcribe, MetaModel.spark],
          ),
          if (d.outcome case final o?) ...[
            const SizedBox(height: Gap.sm),
            Text(
              'Outcome: ${o.label}',
              style: context.text.titleSmall?.copyWith(
                color: context.status.pass,
              ),
            ),
            if ((d.resolutionReason ?? '').isNotEmpty)
              Text(d.resolutionReason!, style: context.text.bodySmall),
            if (d.resolvedAt != null)
              Text(
                'Resolved ${formatSlot(d.resolvedAt)}',
                style: context.text.labelSmall,
              ),
          ] else ...[
            const SizedBox(height: Gap.sm),
            Text(
              'The barber’s payout is on hold until an operator decides.',
              style: context.text.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _DisputeSheet extends ConsumerStatefulWidget {
  const _DisputeSheet({required this.jobId});

  final String jobId;

  @override
  ConsumerState<_DisputeSheet> createState() => _DisputeSheetState();
}

class _DisputeSheetState extends ConsumerState<_DisputeSheet> {
  final _text = TextEditingController();
  UploadFile? _audio;
  Duration? _length;
  bool _sending = false;
  String? _error;
  Dispute? _result;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final d = await container
          .read(apiProvider)
          .openDispute(widget.jobId, audio: _audio, text: _text.text.trim());
      refreshJobIn(container, widget.jobId);
      if (mounted) setState(() => _result = d);
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Padding(
      padding: EdgeInsets.only(
        left: Gap.lg,
        right: Gap.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + Gap.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Report a problem', style: context.text.headlineSmall),
            const SizedBox(height: Gap.md),
            if (result != null) ...[
              DisputeSummaryCard(dispute: result),
              const SizedBox(height: Gap.md),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ] else if (_sending)
              const LoadingView(
                message: 'Listening to your note and writing up the case…',
              )
            else ...[
              Text(
                'Say what went wrong in your own words and language, type '
                'it, or both.',
                style: context.text.bodyMedium,
              ),
              const SizedBox(height: Gap.lg),
              Center(
                child: VoiceRecorderButton(
                  idleLabel: _audio == null
                      ? 'Tap to record'
                      : 'Recorded ${_length!.inSeconds} s · tap to redo',
                  onRecorded: (audio, length) => setState(() {
                    _audio = audio;
                    _length = length;
                  }),
                ),
              ),
              const SizedBox(height: Gap.lg),
              TextField(
                controller: _text,
                minLines: 2,
                maxLines: 4,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Or type what happened',
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
                onPressed: _audio == null && _text.text.trim().isEmpty
                    ? null
                    : _send,
                child: const Text('Send to Fade Call'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
