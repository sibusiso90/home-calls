import 'package:fade_call/core/format.dart';
import 'package:fade_call/core/theme.dart';
import 'package:fade_call/data/api_exception.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/router.dart';
import 'package:fade_call/state/providers.dart';
import 'package:fade_call/ui/widgets/badges.dart';
import 'package:fade_call/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

Future<void> showBookingSheet(
  BuildContext context, {
  required String quoteId,
  required BarberMatch match,
  required String? areaId,
}) => showModalBottomSheet<void>(
  useRootNavigator: true,
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  constraints: const BoxConstraints(maxWidth: 640),
  builder: (_) => BookingSheet(quoteId: quoteId, match: match, areaId: areaId),
);

class BookingSheet extends ConsumerStatefulWidget {
  const BookingSheet({
    required this.quoteId,
    required this.match,
    required this.areaId,
    super.key,
  });

  final String quoteId;
  final BarberMatch match;
  final String? areaId;

  @override
  ConsumerState<BookingSheet> createState() => _BookingSheetState();
}

enum _LocationSource { device, area }

class _BookingSheetState extends ConsumerState<BookingSheet> {
  final _address = TextEditingController();
  ({double lat, double lng, _LocationSource source, double? accuracy})? _point;
  bool _locating = false;
  bool _booking = false;
  String? _error;
  String? _locationNote;

  @override
  void initState() {
    super.initState();
    _useAreaCentre();
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Area? get _area => ref
      .read(areasProvider)
      .value
      ?.where((a) => a.id == widget.areaId)
      .firstOrNull;

  void _useAreaCentre() {
    final area = _area;
    if (area != null) {
      _point = (
        lat: area.lat,
        lng: area.lng,
        source: _LocationSource.area,
        accuracy: null,
      );
    }
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _locationNote = null;
    });
    final fix = await ref.read(locationServiceProvider).currentFix();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (fix != null) {
        _point = (
          lat: fix.lat,
          lng: fix.lng,
          source: _LocationSource.device,
          accuracy: fix.accuracyM,
        );
      } else {
        _useAreaCentre();
        _locationNote =
            "We couldn't get your location, so we'll use the centre of your suburb.";
      }
    });
  }

  Future<void> _book() async {
    final point = _point;
    final slot = widget.match.nextSlot;
    if (_address.text.trim().length < 5) {
      setState(() => _error = 'Enter the street address for the barber.');
      return;
    }
    if (point == null || slot == null) {
      setState(() => _error = 'Use your location so we can find you.');
      return;
    }
    setState(() {
      _booking = true;
      _error = null;
    });
    try {
      final job = await ref
          .read(apiProvider)
          .createJob(
            quoteId: widget.quoteId,
            barberId: widget.match.barber.id,
            slotStart: slot,
            address: _address.text.trim(),
            lat: point.lat,
            lng: point.lng,
          );
      ref.invalidate(jobsProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      GoRouter.of(context).go(Routes.clientJob(job.id, confirmed: true));
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    ref.watch(areasProvider);
    if (_point == null) _useAreaCentre();
    final point = _point;
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
            Text('Book ${m.barber.name}', style: context.text.headlineSmall),
            const SizedBox(height: Gap.xs),
            Row(
              children: [
                TierBadge(tier: m.barber.tier),
                const SizedBox(width: Gap.sm),
                Text(
                  rand(m.price.totalZar),
                  style: context.text.titleLarge?.copyWith(
                    color: context.colors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.lg),
            Panel(
              child: Row(
                children: [
                  Icon(Icons.event_rounded, color: context.colors.primary),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Slot', style: context.text.labelMedium),
                        Text(
                          formatSlot(m.nextSlot),
                          style: context.text.titleMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Gap.md),
            TextField(
              controller: _address,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Street address',
                hintText: '12 Example Rd, Midrand',
                prefixIcon: Icon(Icons.home_outlined),
              ),
            ),
            const SizedBox(height: Gap.md),
            Panel(
              child: Row(
                children: [
                  Icon(
                    point?.source == _LocationSource.device
                        ? Icons.my_location_rounded
                        : Icons.location_searching_rounded,
                    color: context.colors.primary,
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Text(switch (point) {
                      null => 'No location yet',
                      (
                        source: _LocationSource.device,
                        :final accuracy,
                        lat: _,
                        lng: _,
                      ) =>
                        'Using your current location (±${accuracy?.round() ?? '?'} m)',
                      _ =>
                        'Using the centre of ${_area?.name ?? 'your suburb'}',
                    }, style: context.text.bodyMedium),
                  ),
                  TextButton(
                    onPressed: _locating ? null : _locate,
                    child: _locating
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Use my location'),
                  ),
                ],
              ),
            ),
            if (_locationNote != null) ...[
              const SizedBox(height: Gap.sm),
              Text(_locationNote!, style: context.text.bodySmall),
            ],
            if (_error != null) ...[
              const SizedBox(height: Gap.md),
              Text(
                _error!,
                style: context.text.bodyMedium?.copyWith(
                  color: context.status.fail,
                ),
              ),
            ],
            const SizedBox(height: Gap.lg),
            FilledButton(
              onPressed: _booking ? null : _book,
              child: _booking
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text('Confirm booking · ${rand(m.price.totalZar)}'),
            ),
            const SizedBox(height: Gap.sm),
            Text(
              'You pay a deposit to hold the slot. The barber is paid only '
              'after the job is verified.',
              textAlign: TextAlign.center,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
