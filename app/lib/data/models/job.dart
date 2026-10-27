import 'package:fade_call/data/models/barber.dart';
import 'package:fade_call/data/models/dispute.dart';
import 'package:fade_call/data/models/evidence.dart';
import 'package:fade_call/data/models/json.dart';

enum JobStatus {
  booked('Booked'),
  confirmed('Confirmed'),
  inProgress('In progress'),
  verifying('Verifying'),
  verified('Verified'),
  needsReview('In review'),
  failed('Failed'),
  cancelled('Cancelled');

  const JobStatus(this.label);
  final String label;

  String get wire => switch (this) {
    inProgress => 'in_progress',
    needsReview => 'needs_review',
    _ => name,
  };

  static JobStatus parse(String value) => JobStatus.values.firstWhere(
    (s) => s.wire == value,
    orElse: () => throw FormatException('Unknown job status: $value'),
  );

  /// The happy path, used to draw the status timeline.
  static const timeline = [booked, confirmed, inProgress, verifying, verified];
}

enum PaymentStatus {
  depositPending('Deposit pending'),
  depositPaid('Deposit paid'),
  released('Payment released'),
  held('Payment held'),
  refunded('Refunded'),
  partiallyRefunded('Partly refunded'),
  forfeited('Deposit kept');

  const PaymentStatus(this.label);
  final String label;

  static PaymentStatus parse(String? value) => switch (value) {
    'deposit_paid' => depositPaid,
    'released' => released,
    'held' => held,
    'refunded' => refunded,
    'partially_refunded' => partiallyRefunded,
    'forfeited' => forfeited,
    _ => depositPending,
  };
}

final class JobParty {
  const JobParty({required this.id, required this.name, this.tier});

  factory JobParty.fromJson(Json json) => JobParty(
    id: json.str('id'),
    name: json.strOrNull('name') ?? '',
    tier: Tier.parse(json.strOrNull('tier')),
  );

  final String id;
  final String name;
  final Tier? tier;
}

final class Rating {
  const Rating({required this.stars, required this.comment});

  factory Rating.fromJson(Json json) =>
      Rating(stars: json.integer('stars'), comment: json.strOrNull('comment'));

  final int stars;
  final String? comment;
}

final class Job {
  const Job({
    required this.id,
    required this.status,
    required this.barber,
    required this.client,
    required this.cut,
    required this.minutes,
    required this.quoteZar,
    required this.travelBand,
    required this.slotStart,
    required this.slotEnd,
    required this.address,
    required this.lat,
    required this.lng,
    required this.depositUrl,
    required this.paymentStatus,
    required this.evidence,
    required this.rating,
    required this.dispute,
    required this.canRate,
    this.consentedDemo = false,
    this.cancelledAt,
    this.cancelledBy,
    this.cancelReason,
    this.rescheduledAt,
    this.reminderSentAt,
  });

  factory Job.fromJson(Json json) => Job(
    id: json.str('id'),
    status: JobStatus.parse(json.str('status')),
    barber: JobParty.fromJson(json.obj('barber')),
    client: JobParty.fromJson(json.obj('client')),
    cut: json.strOrNull('cut') ?? '',
    minutes: json.intOrNull('minutes') ?? 0,
    quoteZar: json.intOrNull('quote_zar') ?? 0,
    travelBand: json.strOrNull('travel_band'),
    slotStart: json.timeOrNull('slot_start'),
    slotEnd: json.timeOrNull('slot_end'),
    address: json.strOrNull('address') ?? '',
    lat: json.dblOrNull('lat'),
    lng: json.dblOrNull('lng'),
    depositUrl: json.strOrNull('deposit_url'),
    paymentStatus: PaymentStatus.parse(json.strOrNull('payment_status')),
    evidence: switch (json.objOrNull('evidence')) {
      final e? => Evidence.fromJson(e),
      null => null,
    },
    rating: switch (json.objOrNull('rating')) {
      final r? => Rating.fromJson(r),
      null => null,
    },
    dispute: switch (json.objOrNull('dispute')) {
      final d? => Dispute.fromJson(d),
      null => null,
    },
    canRate: json.flag('can_rate'),
    consentedDemo: json.flag('consented_demo'),
    cancelledAt: json.timeOrNull('cancelled_at'),
    cancelledBy: json.strOrNull('cancelled_by'),
    cancelReason: json.strOrNull('cancel_reason'),
    rescheduledAt: json.timeOrNull('rescheduled_at'),
    reminderSentAt: json.timeOrNull('reminder_sent_at'),
  );

  final String id;
  final JobStatus status;
  final JobParty barber;
  final JobParty client;
  final String cut;
  final int minutes;
  final int quoteZar;
  final String? travelBand;
  final DateTime? slotStart;
  final DateTime? slotEnd;
  final String address;
  final double? lat;
  final double? lng;
  final String? depositUrl;
  final PaymentStatus paymentStatus;
  final Evidence? evidence;
  final Rating? rating;
  final Dispute? dispute;
  final bool canRate;

  /// Part of the consented demo set, so its photos are kept after the verdict.
  final bool consentedDemo;

  final DateTime? cancelledAt;

  /// `client` or `barber`.
  final String? cancelledBy;
  final String? cancelReason;
  final DateTime? rescheduledAt;
  final DateTime? reminderSentAt;

  /// Cancel and reschedule are allowed only before the before-photo.
  bool get isChangeable =>
      status == JobStatus.booked || status == JobStatus.confirmed;

  /// A client cancelling closer than this keeps no deposit (backend rule).
  static const lateCancelWindow = Duration(hours: 2);

  bool isLateCancel(DateTime now) =>
      slotStart != null && slotStart!.difference(now) < lateCancelWindow;
}
