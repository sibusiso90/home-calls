import 'package:fade_call/core/format.dart';
import 'package:fade_call/core/theme.dart';
import 'package:fade_call/data/api_exception.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/data/upload_file.dart';
import 'package:fade_call/state/barber_state.dart';
import 'package:fade_call/state/providers.dart';
import 'package:fade_call/ui/widgets/badges.dart';
import 'package:fade_call/ui/widgets/common.dart';
import 'package:fade_call/ui/widgets/consent_gate.dart';
import 'package:fade_call/ui/widgets/portfolio_scores.dart';
import 'package:fade_call/ui/widgets/voice_recorder_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _portfolioTarget = 5;

/// Consent → voice profile → 5 portfolio pairs → grade.
class OnboardingFlow extends ConsumerWidget {
  const OnboardingFlow({required this.barber, super.key});

  final Barber barber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consent = ref.watch(
      consentProvider(ConsentTopic.barberOnboarding.key),
    );
    final step = switch (barber) {
      _ when !consent => 0,
      Barber(profileConfirmed: false) => 1,
      Barber(:final portfolio) when portfolio.length < _portfolioTarget => 2,
      _ => 3,
    };
    return PageList(
      // A new step starts at the top of the page.
      key: ValueKey('onboarding-step-$step'),
      children: [
        _StepHeader(current: step),
        const SizedBox(height: Gap.lg),
        switch (step) {
          0 => ConsentCard(
            topic: ConsentTopic.barberOnboarding,
            onAgree: () => ref
                .read(
                  consentProvider(ConsentTopic.barberOnboarding.key).notifier,
                )
                .accept(),
          ),
          1 => _VoiceProfileStep(barber: barber),
          2 => _PortfolioStep(barber: barber),
          _ => _GradeStep(barber: barber),
        },
      ],
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.current});

  final int current;

  static const _labels = ['Consent', 'Voice profile', 'Portfolio', 'Grade'];

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Step ${current + 1} of ${_labels.length}',
        style: context.text.labelMedium?.copyWith(
          color: context.colors.secondary,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
      const SizedBox(height: 2),
      Text(_labels[current], style: context.text.headlineSmall),
      const SizedBox(height: Gap.md),
      Row(
        children: [
          for (var i = 0; i < _labels.length; i++) ...[
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 6,
                decoration: BoxDecoration(
                  color: i <= current
                      ? (i == current ? Palette.brass : Palette.forest)
                      : Palette.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            if (i < _labels.length - 1) const SizedBox(width: Gap.xs + 2),
          ],
        ],
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Voice profile
// ---------------------------------------------------------------------------

class _VoiceProfileStep extends ConsumerStatefulWidget {
  const _VoiceProfileStep({required this.barber});

  final Barber barber;

  @override
  ConsumerState<_VoiceProfileStep> createState() => _VoiceProfileStepState();
}

class _VoiceProfileStepState extends ConsumerState<_VoiceProfileStep> {
  VoiceNoteResult? _result;
  bool _manual = false;
  bool _uploading = false;
  bool _saving = false;
  String? _error;

  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _years = TextEditingController();
  final _styles = TextEditingController();
  final _languages = TextEditingController();
  final _availability = TextEditingController();
  String? _areaId;

  @override
  void initState() {
    super.initState();
    _fill(widget.barber.profile);
  }

  @override
  void dispose() {
    for (final c in [_name, _years, _styles, _languages, _availability]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(BarberProfile p) {
    _name.text = p.name;
    _years.text = p.yearsCutting?.toString() ?? '';
    _styles.text = p.styles.join(', ');
    _languages.text = p.languages.join(', ');
    _availability.text = p.availability;
    _areaId = p.areaId;
  }

  Future<void> _upload(UploadFile audio, Duration _) async {
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final result = await ref.read(apiProvider).uploadVoiceNote(audio);
      if (!mounted) return;
      setState(() {
        _result = result;
        _fill(result.profile);
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  List<String> _split(String s) =>
      s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  Future<void> _confirm() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final profile = BarberProfile(
        name: _name.text.trim(),
        areaId: _areaId,
        yearsCutting: int.tryParse(_years.text.trim()),
        styles: _split(_styles.text),
        languages: _split(_languages.text),
        availability: _availability.text.trim(),
      );
      await ref.read(apiProvider).confirmProfile(profile);
      ref.invalidate(myBarberProvider);
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final showForm = result != null || _manual;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          padding: const EdgeInsets.all(Gap.lg),
          child: Column(
            children: [
              Text(
                'Tell us about yourself',
                style: context.text.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Gap.xs),
              Text(
                'In any language you like: your name, the area you work in, '
                'how many years you have been cutting, the styles you do and '
                'when you are available.',
                textAlign: TextAlign.center,
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Gap.lg),
              if (_uploading)
                const LoadingView(
                  message: 'Transcribing and reading your voice note…',
                )
              else
                VoiceRecorderButton(
                  onRecorded: _upload,
                  idleLabel: result == null
                      ? 'Tap to record'
                      : 'Tap to record again',
                ),
              if (!showForm && !_uploading)
                TextButton(
                  onPressed: () => setState(() => _manual = true),
                  child: const Text('Type my details instead'),
                ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: Gap.md),
          Callout(
            icon: Icons.error_outline_rounded,
            color: context.status.fail,
            background: context.status.failContainer,
            text: _error!,
          ),
        ],
        if (result != null) ...[
          const SectionHeader(title: 'What we heard'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result.languageDetected != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gap.sm),
                    child: Chip(
                      avatar: const Icon(Icons.translate_rounded, size: 16),
                      label: Text(result.languageDetected!),
                    ),
                  ),
                Text(
                  '“${result.cleanTranscript ?? result.transcript}”',
                  style: context.text.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.md),
          Callout(
            icon: Icons.record_voice_over_rounded,
            title: 'Is this right?',
            text: result.readBack,
          ),
        ],
        if (showForm) ...[
          const SectionHeader(
            title: 'Your profile',
            subtitle: 'Fix anything we got wrong before you confirm.',
          ),
          Panel(child: _buildForm(context)),
          const SizedBox(height: Gap.md),
          FilledButton.icon(
            onPressed: _saving ? null : _confirm,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded),
            label: const Text('Confirm my profile'),
          ),
        ],
      ],
    );
  }

  Widget _buildForm(BuildContext context) {
    final areas = ref.watch(areasProvider);
    return Form(
      key: _form,
      child: Column(
        children: [
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Enter your name' : null,
          ),
          const SizedBox(height: Gap.md),
          switch (areas) {
            AsyncData(:final value) => DropdownButtonFormField<String>(
              initialValue: value.any((a) => a.id == _areaId) ? _areaId : null,
              decoration: const InputDecoration(labelText: 'Area'),
              items: [
                for (final a in value)
                  DropdownMenuItem(value: a.id, child: Text(a.name)),
              ],
              onChanged: (v) => setState(() => _areaId = v),
              validator: (v) => v == null ? 'Choose your area' : null,
            ),
            AsyncError(:final error) => Text(friendlyError(error)),
            _ => const LinearProgressIndicator(),
          },
          const SizedBox(height: Gap.md),
          TextFormField(
            controller: _years,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Years cutting'),
          ),
          const SizedBox(height: Gap.md),
          TextFormField(
            controller: _styles,
            decoration: const InputDecoration(
              labelText: 'Styles',
              helperText: 'Separate with commas, e.g. skin fade, taper',
            ),
          ),
          const SizedBox(height: Gap.md),
          TextFormField(
            controller: _languages,
            decoration: const InputDecoration(
              labelText: 'Languages',
              helperText: 'e.g. isiZulu, English',
            ),
          ),
          const SizedBox(height: Gap.md),
          TextFormField(
            controller: _availability,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Availability'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Portfolio
// ---------------------------------------------------------------------------

class _PortfolioStep extends ConsumerWidget {
  const _PortfolioStep({required this.barber});

  final Barber barber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = barber.portfolio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Callout(
          icon: Icons.photo_library_outlined,
          title: 'Add $_portfolioTarget before/after pairs',
          text:
              'Each pair is scored out of 10 for fade blend, line-up, symmetry '
              'and finish, with a reason for every score.',
        ),
        const SizedBox(height: Gap.md),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: items.length / _portfolioTarget,
            minHeight: 8,
          ),
        ),
        const SizedBox(height: Gap.xs),
        Text(
          '${items.length} of $_portfolioTarget pairs scored',
          style: context.text.labelMedium,
        ),
        const SizedBox(height: Gap.md),
        for (final (i, item) in items.indexed) ...[
          PortfolioCard(
            item: item,
            index: i,
            onExpired: () => ref.invalidate(myBarberProvider),
            onDelete: () async {
              try {
                await ref.read(apiProvider).deletePortfolioItem(item.id);
                ref.invalidate(myBarberProvider);
              } on Object catch (e) {
                if (context.mounted) showSnack(context, friendlyError(e));
              }
            },
          ),
          const SizedBox(height: Gap.sm + 4),
        ],
        if (items.length < _portfolioTarget) _AddPairCard(index: items.length),
      ],
    );
  }
}

class _AddPairCard extends ConsumerStatefulWidget {
  const _AddPairCard({required this.index});

  final int index;

  @override
  ConsumerState<_AddPairCard> createState() => _AddPairCardState();
}

class _AddPairCardState extends ConsumerState<_AddPairCard> {
  UploadFile? _before;
  UploadFile? _after;
  bool _scoring = false;
  String? _error;

  Future<void> _pick({required bool after}) async {
    final file = await ref
        .read(mediaPickerProvider)
        .pickImage(name: after ? 'after' : 'before');
    if (file == null || !mounted) return;
    setState(() => after ? _after = file : _before = file);
  }

  Future<void> _score() async {
    final (before, after) = (_before, _after);
    if (before == null || after == null) return;
    setState(() {
      _scoring = true;
      _error = null;
    });
    try {
      await ref
          .read(apiProvider)
          .addPortfolioItem(before: before, after: after);
      ref.invalidate(myBarberProvider);
      if (mounted) {
        setState(() {
          _before = null;
          _after = null;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _scoring = false);
    }
  }

  @override
  Widget build(BuildContext context) => Panel(
    borderColor: Palette.brass,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Pair ${widget.index + 1}', style: context.text.titleMedium),
        const SizedBox(height: Gap.sm + 4),
        Row(
          children: [
            Expanded(
              child: _PhotoSlot(
                label: 'Before',
                file: _before,
                onTap: _scoring ? null : () => _pick(after: false),
              ),
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: _PhotoSlot(
                label: 'After',
                file: _after,
                onTap: _scoring ? null : () => _pick(after: true),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: Gap.sm),
          Text(
            _error!,
            style: context.text.bodySmall?.copyWith(color: context.status.fail),
          ),
        ],
        const SizedBox(height: Gap.md),
        if (_scoring)
          const LoadingView(
            message: 'Scoring fade blend, line-up, symmetry and finish…',
          )
        else
          FilledButton.icon(
            onPressed: _before != null && _after != null ? _score : null,
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('Score this pair'),
          ),
      ],
    ),
  );
}

class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({required this.label, required this.file, this.onTap});

  final String label;
  final UploadFile? file;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: file == null ? 'Add $label photo' : 'Change $label photo',
    child: AspectRatio(
      aspectRatio: 1,
      child: Material(
        color: context.colors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: file == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_photo_alternate_outlined,
                      color: context.colors.primary,
                      size: 32,
                    ),
                    const SizedBox(height: Gap.xs),
                    Text('Add $label photo', style: context.text.labelLarge),
                  ],
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(file!.bytes, fit: BoxFit.cover),
                    Positioned(
                      left: Gap.sm,
                      top: Gap.sm,
                      child: Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(label),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Grade
// ---------------------------------------------------------------------------

class _GradeStep extends ConsumerStatefulWidget {
  const _GradeStep({required this.barber});

  final Barber barber;

  @override
  ConsumerState<_GradeStep> createState() => _GradeStepState();
}

class _GradeStepState extends ConsumerState<_GradeStep> {
  bool _grading = false;
  String? _error;

  Future<void> _grade() async {
    setState(() {
      _grading = true;
      _error = null;
    });
    try {
      final result = await ref.read(apiProvider).grade();
      ref.read(gradeResultProvider.notifier).set(result);
      ref.invalidate(myBarberProvider);
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _grading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.barber.portfolio;
    final avg = items.isEmpty
        ? 0.0
        : items.map((i) => i.overall).reduce((a, b) => a + b) / items.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          padding: const EdgeInsets.all(Gap.lg),
          child: Column(
            children: [
              Text(
                'Ready to grade',
                style: context.text.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Gap.sm),
              Text(
                'Your ${items.length} pairs average ${avg.toStringAsFixed(1)}. '
                'Grading sets your tier and home-call price band.',
                textAlign: TextAlign.center,
                style: context.text.bodyMedium,
              ),
              const SizedBox(height: Gap.lg),
              const Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.sm,
                alignment: WrapAlignment.center,
                children: [
                  _TierHint(
                    tier: Tier.starter,
                    rule: 'below 6.5',
                    band: (250, 320),
                  ),
                  _TierHint(tier: Tier.pro, rule: '6.5–7.9', band: (320, 420)),
                  _TierHint(tier: Tier.elite, rule: '8.0+', band: (420, 550)),
                ],
              ),
              const SizedBox(height: Gap.lg),
              if (_grading)
                const LoadingView(message: 'Grading your portfolio…')
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _grade,
                    icon: const Icon(Icons.workspace_premium_rounded),
                    label: const Text('Grade my portfolio'),
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
            ],
          ),
        ),
        const SectionHeader(title: 'Your pairs'),
        for (final (i, item) in items.indexed) ...[
          PortfolioCard(
            item: item,
            index: i,
            compact: true,
            onExpired: () => ref.invalidate(myBarberProvider),
          ),
          const SizedBox(height: Gap.sm),
        ],
      ],
    );
  }
}

class _TierHint extends StatelessWidget {
  const _TierHint({required this.tier, required this.rule, required this.band});

  final Tier tier;
  final String rule;
  final (int, int) band;

  @override
  Widget build(BuildContext context) => Container(
    width: 150,
    padding: const EdgeInsets.all(Gap.sm + 4),
    decoration: BoxDecoration(
      color: context.colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: context.colors.outlineVariant),
    ),
    child: Column(
      children: [
        TierBadge(tier: tier),
        const SizedBox(height: Gap.xs + 2),
        Text('Average $rule', style: context.text.labelSmall),
        Text(randRange(band.$1, band.$2), style: context.text.titleSmall),
      ],
    ),
  );
}
