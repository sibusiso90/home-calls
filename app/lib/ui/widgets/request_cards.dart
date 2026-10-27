import 'dart:async';

import 'package:fade_call/core/format.dart';
import 'package:fade_call/core/theme.dart';
import 'package:fade_call/data/api_exception.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/router.dart';
import 'package:fade_call/state/providers.dart';
import 'package:fade_call/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// "9:41 left" until [until], ticking every second; "time's up" after.
class Countdown extends StatefulWidget {
  const Countdown({required this.until, super.key, this.style, this.suffix});

  final DateTime until;
  final TextStyle? style;
  final String? suffix;

  @override
  State<Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<Countdown> {
  late final Timer _timer = Timer.periodic(
    const Duration(seconds: 1),
    (_) => setState(() {}),
  );

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.until.difference(DateTime.now());
    final text = left.isNegative
        ? "time's up"
        : '${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}'
              '${widget.suffix ?? ' left'}';
    return Text(text, style: widget.style);
  }
}

String _windowsText(HomeCallRequest r) =>
    r.windows.map((w) => '${w.label} ${w.hours}').join(' · ');

/// A client's request in My bookings: who it is waiting on, or how it ended.
class ClientRequestCard extends ConsumerWidget {
  const ClientRequestCard({required this.request, super.key});

  final HomeCallRequest request;

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(apiProvider).cancelRequest(request.id);
      ref.invalidate(requestsProvider);
    } on Object catch (e) {
      if (context.mounted) showSnack(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = request;
    final muted = context.text.bodySmall?.copyWith(
      color: context.colors.onSurfaceVariant,
    );
    final (IconData icon, Color color, Widget status) = switch (r) {
      HomeCallRequest(status: RequestStatus.open, broadcast: false) => (
        Icons.hourglass_top_rounded,
        context.status.review,
        Wrap(
          spacing: 4,
          children: [
            Text('Waiting for ${r.chosenBarberName ?? 'your barber'}'),
            if (r.offeredUntil case final until?)
              Countdown(until: until, suffix: ' to accept', style: muted),
          ],
        ),
      ),
      HomeCallRequest(status: RequestStatus.open) => (
        Icons.campaign_outlined,
        context.status.review,
        const Text('Asking barbers nearby'),
      ),
      HomeCallRequest(status: RequestStatus.accepted) => (
        Icons.check_circle_rounded,
        context.status.pass,
        const Text('A barber took it: tap to see the time and pay'),
      ),
      HomeCallRequest(status: RequestStatus.expired) => (
        Icons.event_busy_rounded,
        context.status.fail,
        const Text('No barber could take it. Try another time.'),
      ),
      _ => (
        Icons.cancel_outlined,
        context.colors.outline,
        const Text('Cancelled'),
      ),
    };
    final jobId = r.jobId;
    return Panel(
      key: ValueKey('request-${r.id}'),
      onTap: jobId == null ? null : () => context.go(Routes.clientJob(jobId)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: DefaultTextStyle.merge(
                  style: context.text.titleSmall,
                  child: status,
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.xs),
          Text('${r.cut} · ${r.summary}', style: context.text.bodyMedium),
          Text(_windowsText(r), style: muted),
          if (r.isOpen)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => unawaited(_cancel(context, ref)),
                child: const Text('Cancel request'),
              ),
            ),
        ],
      ),
    );
  }
}

/// A request offered to a barber: pick a start time inside the client's
/// windows and accept, or decline.
class BarberRequestCard extends ConsumerStatefulWidget {
  const BarberRequestCard({required this.request, super.key});

  final HomeCallRequest request;

  @override
  ConsumerState<BarberRequestCard> createState() => _BarberRequestCardState();
}

class _BarberRequestCardState extends ConsumerState<BarberRequestCard> {
  DateTime? _slot;
  bool _busy = false;

  Future<void> _accept() async {
    final slot = _slot;
    if (slot == null) return;
    setState(() => _busy = true);
    try {
      final job = await ref
          .read(apiProvider)
          .acceptRequest(widget.request.id, slotStart: slot);
      ref
        ..invalidate(requestsProvider)
        ..invalidate(jobsProvider);
      if (mounted) context.go(Routes.barberJob(job.id));
    } on Object catch (e) {
      ref.invalidate(requestsProvider);
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).declineRequest(widget.request.id);
    } on Object catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      ref.invalidate(requestsProvider);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final price = r.price;
    final muted = context.text.bodySmall?.copyWith(
      color: context.colors.onSurfaceVariant,
    );
    return Panel(
      key: ValueKey('offer-${r.id}'),
      borderColor: r.offeredToYou ? context.colors.primary : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                r.offeredToYou
                    ? Icons.person_pin_circle_rounded
                    : Icons.campaign_outlined,
                color: context.colors.primary,
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  r.offeredToYou
                      ? '${r.clientName ?? 'A client'} asked for you'
                      : 'Open request nearby',
                  style: context.text.titleSmall,
                ),
              ),
              if (r.offeredToYou && r.offeredUntil != null)
                Countdown(until: r.offeredUntil!, style: muted),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Text('${r.cut} (${r.minutes} min)', style: context.text.titleMedium),
          Text(
            '${r.summary[0].toUpperCase()}${r.summary.substring(1)} · '
            '${r.areaName}'
            '${r.distanceKm == null ? '' : ' · ${formatKm(r.distanceKm!)}'}',
            style: context.text.bodyMedium,
          ),
          if (price != null)
            Text('You earn ${rand(price.totalZar)}', style: muted),
          const SizedBox(height: Gap.md),
          if (r.slots.isEmpty)
            Text("You're booked through the client's windows.", style: muted)
          else ...[
            Text('Pick your start time', style: context.text.labelLarge),
            const SizedBox(height: Gap.sm),
            Wrap(
              spacing: Gap.sm,
              runSpacing: Gap.sm,
              children: [
                for (final s in r.slots)
                  ChoiceChip(
                    label: Text(formatTime(s)),
                    selected: s == _slot,
                    onSelected: _busy ? null : (_) => setState(() => _slot = s),
                  ),
              ],
            ),
          ],
          const SizedBox(height: Gap.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => unawaited(_decline()),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _busy || _slot == null
                      ? null
                      : () => unawaited(_accept()),
                  child: Text(
                    _slot == null
                        ? 'Pick a time'
                        : 'Accept for ${formatTime(_slot)}',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
