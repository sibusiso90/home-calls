import 'package:fade_call/data/models/json.dart';
import 'package:fade_call/data/models/quote.dart';

enum RequestStatus {
  open,
  accepted,
  expired,
  cancelled;

  static RequestStatus parse(String? raw) =>
      values.firstWhere((v) => v.name == raw, orElse: () => open);
}

/// A part of the day a client can ask for; the barber picks the exact start.
enum TimeWindow {
  morning('Morning', '08–12', 8, 12),
  afternoon('Afternoon', '12–17', 12, 17),
  evening('Evening', '17–20', 17, 21);

  const TimeWindow(this.label, this.hours, this.startHour, this.endHour);
  final String label;
  final String hours;
  final int startHour;

  /// Exclusive; the last start time is 20:00.
  final int endHour;

  static TimeWindow? parse(String? raw) =>
      values.where((v) => v.name == raw).firstOrNull;

  /// Whether a barber could still start a cut in this window on [day]
  /// (local date), at least an hour from [now]. Sundays close at 17:00.
  bool open(DateTime day, DateTime now) {
    final sunday = day.weekday == DateTime.sunday;
    final first = sunday ? 9 : 8;
    final last = DateTime(day.year, day.month, day.day, sunday ? 17 : 20);
    final from = DateTime(
      day.year,
      day.month,
      day.day,
      startHour < first ? first : startHour,
    );
    final to = DateTime(day.year, day.month, day.day, endHour);
    final latest = to.isAfter(last) ? last : to.subtract(_step);
    return !from.isAfter(latest) &&
        !latest.isBefore(now.add(const Duration(hours: 1)));
  }

  static const _step = Duration(minutes: 30);
}

/// A client's request for a home call on a day, in one or more time windows.
///
/// The barber fields ([price], [slots], ...) are only set when a barber reads
/// a request offered to them.
final class HomeCallRequest {
  const HomeCallRequest({
    required this.id,
    required this.status,
    required this.day,
    required this.windows,
    required this.summary,
    required this.cut,
    required this.minutes,
    required this.areaName,
    required this.quoteId,
    required this.chosenBarberName,
    required this.offeredUntil,
    required this.broadcast,
    required this.jobId,
    required this.createdAt,
    this.offeredToYou = false,
    this.clientName,
    this.distanceKm,
    this.price,
    this.slots = const [],
  });

  factory HomeCallRequest.fromJson(Json json) => HomeCallRequest(
    id: json.str('id'),
    status: RequestStatus.parse(json.strOrNull('status')),
    day: DateTime.parse(json.str('day')),
    windows: [
      for (final w in json.list('windows', (w) => w.strOrNull('id')))
        ?TimeWindow.parse(w),
    ],
    summary: json.strOrNull('summary') ?? '',
    cut: json.strOrNull('cut') ?? '',
    minutes: json.intOrNull('minutes') ?? 0,
    areaName: json.strOrNull('area_name') ?? '',
    quoteId: json.strOrNull('quote_id'),
    chosenBarberName: json.objOrNull('chosen_barber')?.strOrNull('name'),
    offeredUntil: json.timeOrNull('offered_until'),
    broadcast: json.flag('broadcast'),
    jobId: json.strOrNull('job_id'),
    createdAt: json.timeOrNull('created_at'),
    offeredToYou: json.flag('offered_to_you'),
    clientName: json.strOrNull('client_name'),
    distanceKm: json.dblOrNull('distance_km'),
    price: switch (json.objOrNull('price')) {
      final p? => PriceQuote.fromJson(p),
      null => null,
    },
    slots: json.strings('slots').map(DateTime.parse).toList(),
  );

  final String id;
  final RequestStatus status;

  /// The South African date asked for (no time part).
  final DateTime day;
  final List<TimeWindow> windows;

  /// e.g. "today, afternoon or evening".
  final String summary;
  final String cut;
  final int minutes;
  final String areaName;
  final String? quoteId;
  final String? chosenBarberName;

  /// While the chosen barber still has the request to themselves.
  final DateTime? offeredUntil;

  /// True once every barber in range has been asked.
  final bool broadcast;
  final String? jobId;
  final DateTime? createdAt;

  final bool offeredToYou;
  final String? clientName;
  final double? distanceKm;
  final PriceQuote? price;
  final List<DateTime> slots;

  bool get isOpen => status == RequestStatus.open;
}
