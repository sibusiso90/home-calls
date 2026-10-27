import 'package:fade_call/data/models/json.dart';

enum Tier {
  starter('Starter'),
  pro('Pro'),
  elite('Elite');

  const Tier(this.label);
  final String label;

  static Tier? parse(String? value) =>
      value == null ? null : Tier.values.byName(value);
}

enum BarberStatus {
  onboarding('Onboarding'),
  pendingApproval('Awaiting approval'),
  approved('Approved'),
  rejected('Rejected');

  const BarberStatus(this.label);
  final String label;

  static BarberStatus parse(String value) => switch (value) {
    'onboarding' => onboarding,
    'pending_approval' => pendingApproval,
    'approved' => approved,
    'rejected' => rejected,
    _ => throw FormatException('Unknown barber status: $value'),
  };
}

final class PriceBand {
  const PriceBand({required this.minZar, required this.maxZar});

  factory PriceBand.fromJson(Json json) => PriceBand(
    minZar: json.integer('min_zar'),
    maxZar: json.integer('max_zar'),
  );

  final int minZar;
  final int maxZar;
}

/// The four portfolio criteria, in display order.
enum ScoreCriterion {
  fadeBlend('fade_blend', 'Fade blend'),
  lineUp('line_up', 'Line-up'),
  symmetry('symmetry', 'Symmetry'),
  finish('finish', 'Finish');

  const ScoreCriterion(this.key, this.label);
  final String key;
  final String label;
}

final class PortfolioItem {
  const PortfolioItem({
    required this.id,
    required this.beforeUrl,
    required this.afterUrl,
    required this.scores,
    required this.reasons,
    required this.overall,
    required this.modelVersions,
    this.elapsedMs,
  });

  factory PortfolioItem.fromJson(Json json) {
    final rawScores = json.objOrNull('scores') ?? const {};
    return PortfolioItem(
      id: json.str('id'),
      beforeUrl: json.str('before_url'),
      afterUrl: json.str('after_url'),
      scores: rawScores.map((k, v) => MapEntry(k, (v as num).toDouble())),
      reasons: json.stringMap('reasons'),
      overall: json.dblOrNull('overall') ?? 0,
      modelVersions: json.stringMap('model_versions'),
      elapsedMs: json.intOrNull('elapsed_ms'),
    );
  }

  final String id;
  final String beforeUrl;
  final String afterUrl;
  final Map<String, double> scores;
  final Map<String, String> reasons;
  final double overall;
  final Map<String, String> modelVersions;
  final int? elapsedMs;

  double? score(ScoreCriterion c) => scores[c.key];
  String? reason(ScoreCriterion c) => reasons[c.key];
}

/// The profile extracted from a voice note, editable before confirmation.
final class BarberProfile {
  const BarberProfile({
    required this.name,
    required this.areaId,
    required this.yearsCutting,
    required this.styles,
    required this.languages,
    required this.availability,
  });

  factory BarberProfile.fromJson(Json json) => BarberProfile(
    name: json.strOrNull('name') ?? '',
    areaId: json.strOrNull('area_id'),
    yearsCutting: json.intOrNull('years_cutting'),
    styles: json.strings('styles'),
    languages: json.strings('languages'),
    availability: json.strOrNull('availability') ?? '',
  );

  final String name;
  final String? areaId;
  final int? yearsCutting;
  final List<String> styles;
  final List<String> languages;
  final String availability;

  BarberProfile copyWith({
    String? name,
    String? areaId,
    int? yearsCutting,
    List<String>? styles,
    List<String>? languages,
    String? availability,
  }) => BarberProfile(
    name: name ?? this.name,
    areaId: areaId ?? this.areaId,
    yearsCutting: yearsCutting ?? this.yearsCutting,
    styles: styles ?? this.styles,
    languages: languages ?? this.languages,
    availability: availability ?? this.availability,
  );

  Json toJson() => {
    'name': name,
    'area_id': areaId,
    'years_cutting': yearsCutting,
    'styles': styles,
    'languages': languages,
    'availability': availability,
  };
}

final class Barber {
  const Barber({
    required this.id,
    required this.name,
    required this.areaId,
    required this.areaName,
    required this.languages,
    required this.yearsCutting,
    required this.styles,
    required this.availability,
    required this.tier,
    required this.priceBand,
    required this.verifiedJobs,
    required this.rating,
    required this.status,
    required this.portfolio,
    required this.profileConfirmed,
  });

  factory Barber.fromJson(Json json) => Barber(
    id: json.str('id'),
    name: json.strOrNull('name') ?? '',
    areaId: json.strOrNull('area_id'),
    areaName: json.strOrNull('area_name'),
    languages: json.strings('languages'),
    yearsCutting: json.intOrNull('years_cutting'),
    styles: json.strings('styles'),
    availability: json.strOrNull('availability'),
    tier: Tier.parse(json.strOrNull('tier')),
    priceBand: switch (json.objOrNull('price_band')) {
      final band? => PriceBand.fromJson(band),
      null => null,
    },
    verifiedJobs: json.intOrNull('verified_jobs') ?? 0,
    rating: json.dblOrNull('rating'),
    status: BarberStatus.parse(json.strOrNull('status') ?? 'onboarding'),
    portfolio: json.list('portfolio', PortfolioItem.fromJson),
    profileConfirmed: json.flag('profile_confirmed'),
  );

  final String id;
  final String name;
  final String? areaId;
  final String? areaName;
  final List<String> languages;
  final int? yearsCutting;
  final List<String> styles;
  final String? availability;
  final Tier? tier;
  final PriceBand? priceBand;
  final int verifiedJobs;
  final double? rating;
  final BarberStatus status;
  final List<PortfolioItem> portfolio;
  final bool profileConfirmed;

  /// Graded and past onboarding: show the profile card rather than the stepper.
  bool get isOnboarded => status != BarberStatus.onboarding && tier != null;

  BarberProfile get profile => BarberProfile(
    name: name,
    areaId: areaId,
    yearsCutting: yearsCutting,
    styles: styles,
    languages: languages,
    availability: availability ?? '',
  );
}

final class VoiceNoteResult {
  const VoiceNoteResult({
    required this.transcript,
    required this.languageDetected,
    required this.profile,
    required this.readBack,
    required this.modelVersions,
    this.cleanTranscript,
    this.elapsedMs,
  });

  factory VoiceNoteResult.fromJson(Json json) => VoiceNoteResult(
    transcript: json.strOrNull('transcript') ?? '',
    cleanTranscript: json.strOrNull('clean_transcript'),
    elapsedMs: json.intOrNull('elapsed_ms'),
    languageDetected: switch (json.strOrNull('language_detected')) {
      final l? when l.trim().isNotEmpty => l,
      _ => null,
    },
    profile: BarberProfile.fromJson(json.obj('profile')),
    readBack: json.strOrNull('read_back') ?? '',
    modelVersions: json.stringMap('model_versions'),
  );

  final String transcript;

  /// A tidied version of the transcript, when the model provides one.
  final String? cleanTranscript;
  final int? elapsedMs;
  final String? languageDetected;
  final BarberProfile profile;
  final String readBack;
  final Map<String, String> modelVersions;
}

final class GradeResult {
  const GradeResult({
    required this.barber,
    required this.tier,
    required this.average,
    required this.summary,
  });

  factory GradeResult.fromJson(Json json) => GradeResult(
    barber: Barber.fromJson(json.obj('barber')),
    tier: Tier.parse(json.strOrNull('tier')) ?? Tier.starter,
    average: json.dblOrNull('average') ?? 0,
    summary: json.strOrNull('summary') ?? '',
  );

  final Barber barber;
  final Tier tier;
  final double average;
  final String summary;
}
