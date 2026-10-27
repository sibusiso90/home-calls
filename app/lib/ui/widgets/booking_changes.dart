import 'dart:async';

import 'package:fade_call/core/format.dart';
import 'package:fade_call/core/theme.dart';
import 'package:fade_call/data/api_exception.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/state/providers.dart';
import 'package:fade_call/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reschedule (client) and cancel (client or barber) before the before-photo.
class BookingChangesPanel extends ConsumerStatefulWidget {
  const BookingChangesPanel({required this.job, required this.role, super.key});

  final Job job;
  final Role role;

  @override
  ConsumerState<BookingChangesPanel> createState() =>
      _BookingChangesPanelState();
}

class _BookingChangesPanelState extends ConsumerState<BookingChangesPanel> {
  bool _busy = false;

  Future<void> _cancel() async {
    final container = ProviderScope.containerOf(context, listen: false);
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => CancelBookingDialog(
        job: widget.job,
        role: widget.role,
        now: DateTime.now(),
      ),
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final job = await container
          .read(apiProvider)
          .cancelJob(widget.job.id, reason: reason);
      refreshJobIn(container, widget.job.id);
      if (mounted) {
        showSnack(context, switch (job.paymentStatus) {
          PaymentStatus.refunded =>
            'Booking cancelled. The deposit is refunded.',
          PaymentStatus.forfeited =>
            'Booking cancelled. The deposit is kept (late cancellation).',
          _ => 'Booking cancelled.',
        });
      }
    } on Object catch (e) {
      refreshJobIn(container, widget.job.id);
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reschedule() async {
    final container = ProviderScope.containerOf(context, listen: false);
    final moved = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => RescheduleSheet(job: widget.job),
    );
    if (moved ?? false) {
      refreshJobIn(container, widget.job.id);
      if (mounted) {
        showSnack(context, 'Moved. Your barber will re-confirm the new time.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.job.isChangeable) return const SizedBox.shrink();
    final client = widget.role == Role.client;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            client ? 'Need to change your booking?' : 'Can\'t make it?',
            style: context.text.titleMedium,
          ),
          const SizedBox(height: Gap.xs),
          Text(
            client
                ? 'You can move or cancel until the barber takes the before photo.'
                : 'Cancel before you take the before photo. The client is told '
                      'straight away and any deposit is refunded.',
            style: context.text.bodySmall,
          ),
          const SizedBox(height: Gap.md),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              if (client)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _reschedule,
                  icon: const Icon(Icons.update_rounded),
                  label: const Text('Reschedule'),
                ),
              OutlinedButton.icon(
                key: const ValueKey('cancel-booking'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.status.fail,
                  side: BorderSide(color: context.status.fail),
                ),
                onPressed: _busy ? null : _cancel,
                icon: const Icon(Icons.event_busy_rounded),
                label: Text(client ? 'Cancel booking' : 'Cancel job'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Asks for a reason and spells out what happens to the deposit.
/// Pops with the reason, or null if the user keeps the booking.
class CancelBookingDialog extends StatefulWidget {
  const CancelBookingDialog({
    required this.job,
    required this.role,
    required this.now,
    super.key,
  });

  final Job job;
  final Role role;
  final DateTime now;

  @override
  State<CancelBookingDialog> createState() => _CancelBookingDialogState();
}

class _CancelBookingDialogState extends State<CancelBookingDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final client = widget.role == Role.client;
    final paid = job.paymentStatus == PaymentStatus.depositPaid;
    final late = client && job.isLateCancel(widget.now);
    final hours = Job.lateCancelWindow.inHours;
    final Widget consequence = switch ((client, paid, late)) {
      (true, true, true) => Callout.warning(
        context,
        'Your slot starts in less than $hours hours, so the deposit is kept '
        'to cover the barber\'s time.',
        title: 'Late cancellation: deposit kept',
      ),
      (true, true, false) => Callout(
        icon: Icons.undo_rounded,
        text:
            'Your deposit will be refunded. Cancelling less than $hours hours '
            'before the slot keeps the deposit.',
      ),
      (true, false, _) => Callout(
        text:
            'No deposit has been paid, so there is nothing to refund. '
            'Cancelling less than $hours hours before a paid slot keeps the deposit.',
      ),
      (false, _, _) => Callout(
        text: paid
            ? 'The client\'s deposit is refunded in full and they are told straight away.'
            : 'The client is told straight away.',
      ),
    };
    return AlertDialog(
      title: Text(client ? 'Cancel this booking?' : 'Cancel this job?'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${job.cut.isEmpty ? 'Haircut' : job.cut} · ${formatSlot(job.slotStart)}',
              style: context.text.titleSmall,
            ),
            const SizedBox(height: Gap.md),
            KeyedSubtree(
              key: ValueKey(late ? 'late-cancel-warning' : 'cancel-note'),
              child: consequence,
            ),
            const SizedBox(height: Gap.md),
            TextField(
              key: const ValueKey('cancel-reason'),
              controller: _reason,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'e.g. Something came up at work',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(client ? 'Keep booking' : 'Keep job'),
        ),
        FilledButton(
          key: const ValueKey('confirm-cancel'),
          style: FilledButton.styleFrom(backgroundColor: context.status.fail),
          onPressed: _reason.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _reason.text.trim()),
          child: Text(client ? 'Cancel booking' : 'Cancel job'),
        ),
      ],
    );
  }
}

/// Lets the client pick another free slot with the same barber.
class RescheduleSheet extends ConsumerStatefulWidget {
  const RescheduleSheet({required this.job, super.key});

  final Job job;

  @override
  ConsumerState<RescheduleSheet> createState() => _RescheduleSheetState();
}

class _RescheduleSheetState extends ConsumerState<RescheduleSheet> {
  DateTime? _picked;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    final slot = _picked;
    if (slot == null) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final slots = barberSlotsProvider(widget.job.barber.id);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await container
          .read(apiProvider)
          .rescheduleJob(widget.job.id, slotStart: slot);
      container.invalidate(slots);
      if (mounted) Navigator.pop(context, true);
    } on Object catch (e) {
      container.invalidate(slots);
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final slots = ref.watch(barberSlotsProvider(widget.job.barber.id));
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Pick a new time', style: context.text.headlineSmall),
          const SizedBox(height: Gap.xs),
          Text(
            'Now: ${formatSlot(widget.job.slotStart)} with ${widget.job.barber.name}. '
            'The barber re-confirms the new time.',
            style: context.text.bodySmall,
          ),
          const SizedBox(height: Gap.md),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: AsyncView(
              value: slots,
              onRetry: () =>
                  ref.invalidate(barberSlotsProvider(widget.job.barber.id)),
              isEmpty: (s) => s.isEmpty,
              empty: const MessageView(
                icon: Icons.event_busy_rounded,
                title: 'No free slots',
                message: 'This barber is fully booked for the next two weeks.',
              ),
              builder: (list) => SingleChildScrollView(
                child: Wrap(
                  spacing: Gap.sm,
                  runSpacing: Gap.sm,
                  children: [
                    for (final s in list)
                      ChoiceChip(
                        label: Text(formatSlot(s)),
                        selected: _picked == s,
                        onSelected: (_) => setState(() => _picked = s),
                      ),
                  ],
                ),
              ),
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
            onPressed: _picked == null || _saving
                ? null
                : () => unawaited(_save()),
            child: Text(
              _picked == null
                  ? 'Choose a slot'
                  : 'Move to ${formatSlot(_picked)}',
            ),
          ),
        ],
      ),
    );
  }
}
