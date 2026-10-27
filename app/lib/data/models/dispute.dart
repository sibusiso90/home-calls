import 'package:fade_call/data/models/job.dart';
import 'package:fade_call/data/models/json.dart';

enum DisputeOutcome {
  release('Release payment'),
  refund('Full refund'),
  partialRefund('Partial refund');

  const DisputeOutcome(this.label);
  final String label;

  String get wire => switch (this) {
    release => 'release',
    refund => 'refund',
    partialRefund => 'partial_refund',
  };

  static DisputeOutcome? parse(String? value) => switch (value) {
    'release' => release,
    'refund' => refund,
    'partial_refund' => partialRefund,
    _ => null,
  };
}

final class Dispute {
  const Dispute({
    required this.id,
    required this.jobId,
    required this.transcript,
    required this.summary,
    required this.clientClaim,
    required this.evidenceNotes,
    required this.suggestedOutcome,
    required this.outcome,
    required this.createdAt,
    this.job,
    this.resolutionReason,
    this.resolvedAt,
  });

  factory Dispute.fromJson(Json json) => Dispute(
    id: json.str('id'),
    jobId: json.str('job_id'),
    transcript: json.strOrNull('transcript') ?? '',
    summary: json.strOrNull('summary') ?? '',
    clientClaim: json.strOrNull('client_claim'),
    evidenceNotes: json.strOrNull('evidence_notes'),
    suggestedOutcome: DisputeOutcome.parse(json.strOrNull('suggested_outcome')),
    outcome: DisputeOutcome.parse(json.strOrNull('outcome')),
    createdAt: json.timeOrNull('created_at'),
    resolutionReason: json.strOrNull('resolution_reason'),
    resolvedAt: json.timeOrNull('resolved_at'),
    job: switch (json.objOrNull('job')) {
      final j? => Job.fromJson(j),
      null => null,
    },
  );

  final String id;
  final String jobId;
  final String transcript;
  final String summary;
  final String? clientClaim;
  final String? evidenceNotes;
  final DisputeOutcome? suggestedOutcome;
  final DisputeOutcome? outcome;
  final DateTime? createdAt;
  final String? resolutionReason;
  final DateTime? resolvedAt;

  /// `/ops/disputes` embeds the job; elsewhere it is absent.
  final Job? job;

  bool get isOpen => outcome == null;
}
