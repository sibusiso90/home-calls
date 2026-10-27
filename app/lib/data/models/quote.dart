import 'package:fade_call/data/models/barber.dart';
import 'package:fade_call/data/models/json.dart';

/// How the client chose the cut on a quote.
enum CutSource {
  reference,
  catalog,
  suggested;

  static CutSource parse(String? raw) =>
      values.firstWhere((v) => v.name == raw, orElse: () => reference);
}

/// A cut from the catalog a client can pick instead of sending a photo.
final class Cut {
  const Cut({
    required this.id,
    required this.name,
    required this.description,
    required this.minutes,
    required this.styles,
    this.imageUrl,
  });

  factory Cut.fromJson(Json json) => Cut(
    id: json.str('id'),
    name: json.str('name'),
    description: json.strOrNull('description') ?? '',
    minutes: json.intOrNull('minutes') ?? 0,
    styles: json.strings('styles'),
    imageUrl: json.strOrNull('image_url'),
  );

  final String id;
  final String name;
  final String description;
  final int minutes;
  final List<String> styles;

  /// Public picture of the cut: a real photo once uploaded, else an illustration.
  final String? imageUrl;
}

/// A catalog cut Muse Spark thinks suits the client's face.
final class CutSuggestion {
  const CutSuggestion({
    required this.cutId,
    required this.name,
    required this.minutes,
    required this.why,
    this.imageUrl,
  });

  factory CutSuggestion.fromJson(Json json) => CutSuggestion(
    cutId: json.str('cut_id'),
    name: json.strOrNull('name') ?? '',
    minutes: json.intOrNull('minutes') ?? 0,
    why: json.strOrNull('why') ?? '',
    imageUrl: json.strOrNull('image_url'),
  );

  final String cutId;
  final String name;
  final int minutes;
  final String why;
  final String? imageUrl;
}

final class Quote {
  const Quote({
    required this.id,
    required this.cutName,
    required this.cutSource,
    required this.cutId,
    required this.minutes,
    required this.fitIssues,
    required this.reasons,
    required this.faceAdvice,
    required this.suggestions,
    required this.selfieUrl,
    required this.referenceUrl,
    required this.selfieOverlayUrl,
    required this.referenceOverlayUrl,
    required this.areaId,
    required this.elapsedMs,
    required this.modelVersions,
    this.cutImageUrl,
  });

  factory Quote.fromJson(Json json) => Quote(
    id: json.str('id'),
    cutName: json.strOrNull('cut_name') ?? '',
    cutSource: CutSource.parse(json.strOrNull('cut_source')),
    cutId: json.strOrNull('cut_id'),
    cutImageUrl: json.strOrNull('cut_image_url'),
    minutes: json.intOrNull('minutes') ?? 0,
    fitIssues: json.strings('fit_issues'),
    reasons: json.strOrNull('reasons') ?? '',
    faceAdvice: json.strOrNull('face_advice'),
    suggestions: json.list('suggestions', CutSuggestion.fromJson),
    selfieUrl: json.strOrNull('selfie_url'),
    referenceUrl: json.strOrNull('reference_url'),
    selfieOverlayUrl: json.strOrNull('selfie_overlay_url'),
    referenceOverlayUrl: json.strOrNull('reference_overlay_url'),
    areaId: json.strOrNull('area_id'),
    elapsedMs: json.intOrNull('elapsed_ms'),
    modelVersions: json.stringMap('model_versions'),
  );

  final String id;
  final String cutName;
  final CutSource cutSource;
  final String? cutId;

  /// Picture of the quoted catalog cut; null for a custom cut from a reference.
  final String? cutImageUrl;
  final int minutes;
  final List<String> fitIssues;
  final String reasons;
  final String? faceAdvice;
  final List<CutSuggestion> suggestions;
  final String? selfieUrl;
  final String? referenceUrl;
  final String? selfieOverlayUrl;
  final String? referenceOverlayUrl;
  final String? areaId;
  final int? elapsedMs;
  final Map<String, String> modelVersions;
}

final class PriceQuote {
  const PriceQuote({
    required this.tierRateZar,
    required this.timeZar,
    required this.travelZar,
    required this.totalZar,
  });

  factory PriceQuote.fromJson(Json json) => PriceQuote(
    tierRateZar: json.integer('tier_rate_zar'),
    timeZar: json.integer('time_zar'),
    travelZar: json.integer('travel_zar'),
    totalZar: json.integer('total_zar'),
  );

  final int tierRateZar;
  final int timeZar;
  final int travelZar;
  final int totalZar;
}

final class MatchBarber {
  const MatchBarber({
    required this.id,
    required this.name,
    required this.tier,
    required this.verifiedJobs,
    required this.rating,
    required this.areaName,
    required this.styles,
    required this.thumbnailUrl,
  });

  factory MatchBarber.fromJson(Json json) => MatchBarber(
    id: json.str('id'),
    name: json.strOrNull('name') ?? '',
    tier: Tier.parse(json.strOrNull('tier')),
    verifiedJobs: json.intOrNull('verified_jobs') ?? 0,
    rating: json.dblOrNull('rating'),
    areaName: json.strOrNull('area_name'),
    styles: json.strings('styles'),
    thumbnailUrl: json.strOrNull('thumbnail_url'),
  );

  final String id;
  final String name;
  final Tier? tier;
  final int verifiedJobs;
  final double? rating;
  final String? areaName;
  final List<String> styles;
  final String? thumbnailUrl;
}

final class BarberMatch {
  const BarberMatch({
    required this.barber,
    required this.distanceKm,
    required this.travelBand,
    required this.price,
    required this.nextSlot,
    required this.score,
  });

  factory BarberMatch.fromJson(Json json) => BarberMatch(
    barber: MatchBarber.fromJson(json.obj('barber')),
    distanceKm: json.dblOrNull('distance_km') ?? 0,
    travelBand: json.strOrNull('travel_band') ?? '',
    price: PriceQuote.fromJson(json.obj('price')),
    nextSlot: json.timeOrNull('next_slot'),
    score: json.dblOrNull('score') ?? 0,
  );

  final MatchBarber barber;
  final double distanceKm;
  final String travelBand;
  final PriceQuote price;
  final DateTime? nextSlot;
  final double score;
}
