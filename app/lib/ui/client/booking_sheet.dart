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
  required BarberMatch? match,
  required String? areaId,
  int? minutes,
}) => showModalBottomSheet<void>(
  useRootNavigator: true,
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  constraints: const BoxConstraints(maxWidth: 640),
  builder: (_) => BookingSheet(
    quoteId: quoteId,
    match: match,
    areaId: areaId,
    minutes: minutes,
  ),
);

/// The client asks for a home call on a day, in one or more time windows.
///
/// With a [match], that barber has 10 minutes to accept before every barber in
/// range is asked; without one, everyone in range is asked straight away. The
/// barber who accepts picks the exact start time.
class BookingSheet extends ConsumerStatefulWidget {
  const BookingSheet({
    required this.quoteId,
    required this.match,
    required this.areaId,
    super.key,
    this.minutes,
  });

  final String quoteId;
  final BarberMatch? match;
  final String? areaId;

  /// The quoted cut's length, so only times it fits into are offered.
  final int? minutes;

  @override
  ConsumerState<BookingSheet> createState() => _BookingSheetState();
}

enum _LocationSource { device, area }

class _BookingSheetState extends ConsumerState<BookingSheet> {
  final _address = TextEditingController();
  ({double lat, double lng, _LocationSource source, double? accuracy})? _point;
  final DateTime _now = DateTime.now();
  late DateTime _day = _firstDay();
  final Set<TimeWindow> _windows = {};
  bool _locating = false;
  bool _booking = false;
  String? _error;
  String? _locationNote;

  List<DateTime> get _days => [
    for (var i = 0; i < 7; i++)
      DateTime(_now.year, _now.month, _now.day).add(Duration(days: i)),
  ];

  bool _hasWindow(DateTime day) =>
      TimeWindow.values.any((w) => w.open(day, _now));

  DateTime _firstDay() => _days.firstWhere(_hasWindow);

  void _pickDay(DateTime day) => setState(() {
    _day = day;
    _windows.removeWhere((w) => !w.open(day, _now));
  });

  String _dayLabel(DateTime day) =>
      switch (day.difference(_days.first).inDays) {
        0 => 'Today',
        1 => 'Tomorrow',
        _ => formatDay(day),
      };

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
    if (_windows.isEmpty) {
      setState(
        () => _error = 'Pick when suits you: morning, afternoon or evening.',
      );
      return;
    }
    if (_address.text.trim().length < 5) {
      setState(() => _error = 'Enter the street address for the barber.');
      return;
    }
    if (point == null) {
      setState(() => _error = 'Use your location so we can find you.');
      return;
    }
    setState(() {
      _booking = true;
      _error = null;
    });
    try {
      await ref
          .read(apiProvider)
          .createRequest(
            quoteId: widget.quoteId,
            day: _day,
            windows: [
              for (final w in TimeWindow.values)
                if (_windows.contains(w)) w,
            ],
            address: _address.text.trim(),
            lat: point.lat,
            lng: point.lng,
            barberId: widget.match?.barber.id,
          );
      ref.invalidate(requestsProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      GoRouter.of(context).go(Routes.clientBookings);
      showSnack(
        context,
        widget.match == null
            ? 'Request sent to barbers near you.'
            : 'Request sent to ${widget.match!.barber.name}.',
      );
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
            Text(
              m == null ? 'Ask barbers near you' : 'Ask ${m.barber.name}',
              style: context.text.headlineSmall,
            ),
            const SizedBox(height: Gap.xs),
            if (m != null)
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
              )
            else
              Text(
                'Every verified barber in range gets it. Price depends on '
                'who takes it; you see it before you pay.',
                style: context.text.bodySmall,
              ),
            const SizedBox(height: Gap.lg),
            Text('Which day?', style: context.text.titleSmall),
            const SizedBox(height: Gap.sm),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final d in _days) ...[
                    ChoiceChip(
                      label: Text(_dayLabel(d)),
                      selected: d == _day,
                      onSelected: _hasWindow(d) ? (_) => _pickDay(d) : null,
                    ),
                    const SizedBox(width: Gap.sm),
                  ],
                ],
              ),
            ),
            const SizedBox(height: Gap.md),
            Text('When suits you?', style: context.text.titleSmall),
            const SizedBox(height: Gap.xs),
            Text(
              'Pick one or more. The barber who takes the job sets the exact time.',
              style: context.text.bodySmall,
            ),
            const SizedBox(height: Gap.sm),
            Wrap(
              spacing: Gap.sm,
              runSpacing: Gap.sm,
              children: [
                for (final w in TimeWindow.values)
                  FilterChip(
                    key: ValueKey('window-${w.name}'),
                    label: Text('${w.label} ${w.hours}'),
                    selected: _windows.contains(w),
                    onSelected: w.open(_day, _now)
                        ? (on) => setState(
                            () => on ? _windows.add(w) : _windows.remove(w),
                          )
                        : null,
                  ),
              ],
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
                  : Text(
                      m == null
                          ? 'Send to barbers nearby'
                          : 'Send request to ${m.barber.name}',
                    ),
            ),
            const SizedBox(height: Gap.sm),
            Text(
              m == null
                  ? 'The first barber to accept takes the job and picks the time. '
                        'You pay the deposit once someone accepts.'
                  : '${m.barber.name} has 10 minutes to accept. If not, we ask '
                        'other verified barbers nearby. You pay the deposit once '
                        'someone accepts.',
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
