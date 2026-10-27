import 'package:fade_call/data/models/json.dart';

enum CheckResult {
  pass,
  fail,
  uncertain;

  static CheckResult parse(String? value) => switch (value) {
    'pass' => pass,
    'fail' => fail,
    _ => uncertain,
  };
}

enum Verdict {
  pass('Pass'),
  needsReview('Needs review'),
  fail('Fail');

  const Verdict(this.label);
  final String label;

  static Verdict? parse(String? value) => switch (value) {
    'pass' => pass,
    'needs_review' => needsReview,
    'fail' => fail,
    _ => null,
  };
}

/// The checks the backend runs, in the order they are shown.
enum CheckKind {
  beforeTimestamp('before_timestamp', 'Before photo time'),
  beforeGps('before_gps', 'Before photo location'),
  afterTimestamp('after_timestamp', 'After photo time'),
  afterGps('after_gps', 'After photo location'),
  samePerson('same_person', 'Same person'),
  hairChanged('hair_changed', 'Hair region changed'),
  cutMatch('cut_match', 'Matches the ordered cut');

  const CheckKind(this.key, this.label);
  final String key;
  final String label;

  /// Turns a backend verdict reason such as `cut_match uncertain` into
  /// `Matches the ordered cut: uncertain`. Free-text reasons pass through.
  static String describeReason(String reason) {
    final space = reason.indexOf(' ');
    final key = space == -1 ? reason : reason.substring(0, space);
    for (final kind in values) {
      if (kind.key == key) {
        return space == -1
            ? kind.label
            : '${kind.label}: ${reason.substring(space + 1)}';
      }
    }
    return reason;
  }
}

final class EvidenceCheck {
  const EvidenceCheck({
    required this.result,
    required this.reason,
    this.confidence,
    this.changeRatio,
    this.distanceM,
  });

  factory EvidenceCheck.fromJson(Json json) => EvidenceCheck(
    result: CheckResult.parse(json.strOrNull('result')),
    reason: json.strOrNull('reason') ?? '',
    confidence: json.dblOrNull('confidence'),
    changeRatio: json.dblOrNull('change_ratio'),
    distanceM: json.dblOrNull('distance_m'),
  );

  final CheckResult result;
  final String reason;
  final double? confidence;
  final double? changeRatio;

  /// GPS checks: metres from the booking address.
  final double? distanceM;
}

final class Evidence {
  const Evidence({
    required this.jobId,
    required this.beforeUrl,
    required this.afterUrl,
    required this.beforeOverlayUrl,
    required this.afterOverlayUrl,
    required this.checks,
    required this.verdict,
    required this.verdictReasons,
    required this.decidedBy,
    required this.modelVersions,
    this.operatorReason,
    this.purgedAt,
    this.elapsedMs,
  });

  factory Evidence.fromJson(Json json) {
    final raw = json.objOrNull('checks') ?? const {};
    final checks = <CheckKind, EvidenceCheck>{
      for (final kind in CheckKind.values)
        if (raw[kind.key] case final Map<dynamic, dynamic> c)
          kind: EvidenceCheck.fromJson(c.cast<String, dynamic>()),
    };
    return Evidence(
      jobId: json.str('job_id'),
      beforeUrl: json.strOrNull('before_url'),
      afterUrl: json.strOrNull('after_url'),
      beforeOverlayUrl: json.strOrNull('before_overlay_url'),
      afterOverlayUrl: json.strOrNull('after_overlay_url'),
      checks: checks,
      verdict: Verdict.parse(json.strOrNull('verdict')),
      verdictReasons: json.strings('verdict_reasons'),
      decidedBy: json.strOrNull('decided_by'),
      modelVersions: json.stringMap('model_versions'),
      operatorReason: json.strOrNull('operator_reason'),
      purgedAt: json.timeOrNull('purged_at'),
      elapsedMs: json.intOrNull('elapsed_ms'),
    );
  }

  final String jobId;
  final String? beforeUrl;
  final String? afterUrl;
  final String? beforeOverlayUrl;
  final String? afterOverlayUrl;
  final Map<CheckKind, EvidenceCheck> checks;
  final Verdict? verdict;
  final List<String> verdictReasons;
  final String? decidedBy;
  final Map<String, String> modelVersions;
  final String? operatorReason;

  /// Model time from the after photo arriving to the verdict.
  final int? elapsedMs;

  /// Set when the raw photos were deleted under the retention policy.
  final DateTime? purgedAt;

  bool get isPurged => purgedAt != null;

  bool get decidedByOperator => decidedBy == 'operator';
}
