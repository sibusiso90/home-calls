import 'package:fade_call/data/models/barber.dart';
import 'package:fade_call/data/models/job.dart';
import 'package:fade_call/data/models/json.dart';

final class OpsSummary {
  const OpsSummary({
    required this.barbersPending,
    required this.jobsNeedsReview,
    required this.openDisputes,
    required this.payoutsReleasedZar,
    this.jobsTotal = 0,
    this.verifiedJobs = 0,
    this.decidedJobs = 0,
    this.passRate,
    this.avgVerdictMs,
  });

  factory OpsSummary.fromJson(Json json) => OpsSummary(
    barbersPending: json.intOrNull('barbers_pending') ?? 0,
    jobsNeedsReview: json.intOrNull('jobs_needs_review') ?? 0,
    openDisputes: json.intOrNull('open_disputes') ?? 0,
    payoutsReleasedZar: json.intOrNull('payouts_released_zar') ?? 0,
    jobsTotal: json.intOrNull('jobs_total') ?? 0,
    verifiedJobs: json.intOrNull('verified_jobs') ?? 0,
    decidedJobs: json.intOrNull('decided_jobs') ?? 0,
    passRate: json.dblOrNull('pass_rate'),
    avgVerdictMs: json.intOrNull('avg_verdict_ms'),
  );

  final int barbersPending;
  final int jobsNeedsReview;
  final int openDisputes;
  final int payoutsReleasedZar;
  final int jobsTotal;
  final int verifiedJobs;
  final int decidedJobs;

  /// Share of decided jobs whose verdict is pass; null when none are decided.
  final double? passRate;
  final int? avgVerdictMs;
}

final class BarberRatingEntry {
  const BarberRatingEntry({
    required this.jobId,
    required this.stars,
    required this.comment,
    required this.clientName,
    required this.createdAt,
  });

  factory BarberRatingEntry.fromJson(Json json) => BarberRatingEntry(
    jobId: json.str('job_id'),
    stars: json.integer('stars'),
    comment: json.strOrNull('comment'),
    clientName: json.strOrNull('client_name') ?? '',
    createdAt: json.timeOrNull('created_at'),
  );

  final String jobId;
  final int stars;
  final String? comment;
  final String clientName;
  final DateTime? createdAt;
}

/// `GET /ops/barbers/{id}`: a barber with their jobs and ratings.
final class BarberDetail {
  const BarberDetail({
    required this.barber,
    required this.jobs,
    required this.ratings,
  });

  factory BarberDetail.fromJson(Json json) => BarberDetail(
    barber: Barber.fromJson(json.obj('barber')),
    jobs: json.list('jobs', Job.fromJson),
    ratings: json.list('ratings', BarberRatingEntry.fromJson),
  );

  final Barber barber;
  final List<Job> jobs;
  final List<BarberRatingEntry> ratings;
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
