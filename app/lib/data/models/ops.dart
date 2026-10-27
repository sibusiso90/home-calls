import 'package:fade_call/data/models/json.dart';

final class OpsSummary {
  const OpsSummary({
    required this.barbersPending,
    required this.jobsNeedsReview,
    required this.openDisputes,
    required this.payoutsReleasedZar,
  });

  factory OpsSummary.fromJson(Json json) => OpsSummary(
    barbersPending: json.intOrNull('barbers_pending') ?? 0,
    jobsNeedsReview: json.intOrNull('jobs_needs_review') ?? 0,
    openDisputes: json.intOrNull('open_disputes') ?? 0,
    payoutsReleasedZar: json.intOrNull('payouts_released_zar') ?? 0,
  );

  final int barbersPending;
  final int jobsNeedsReview;
  final int openDisputes;
  final int payoutsReleasedZar;
}

final class Payout {
  const Payout({
    required this.jobId,
    required this.barberId,
    required this.barberName,
    required this.amountZar,
    required this.status,
    required this.createdAt,
  });

  factory Payout.fromJson(Json json) => Payout(
    jobId: json.str('job_id'),
    barberId: json.strOrNull('barber_id') ?? '',
    barberName: json.strOrNull('barber_name') ?? '',
    amountZar: json.intOrNull('amount_zar') ?? 0,
    status: json.strOrNull('status') ?? '',
    createdAt: json.timeOrNull('created_at'),
  );

  final String jobId;
  final String barberId;
  final String barberName;
  final int amountZar;
  final String status;
  final DateTime? createdAt;
}
