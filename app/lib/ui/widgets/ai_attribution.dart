import 'package:fade_call/core/theme.dart';
import 'package:flutter/material.dart';

/// The Meta models whose output appears on screen.
enum MetaModel {
  spark('spark', 'Muse Spark', Icons.auto_awesome_rounded),
  sam('sam', 'SAM 3.1', Icons.blur_on_rounded),
  transcribe('transcribe', 'Voice Transcribe', Icons.graphic_eq_rounded);

  const MetaModel(this.key, this.label, this.icon);

  /// Key used in the API's `model_versions` maps.
  final String key;
  final String label;
  final IconData icon;

  /// The models named in a `model_versions` map, in display order.
  static List<MetaModel> from(Map<String, String> versions) => [
    for (final m in values)
      if (versions.containsKey(m.key)) m,
  ];
}

/// "Muse Spark · 1.2 s": names the model behind a piece of output, so every
/// AI moment on screen is attributable. The tooltip carries the exact version.
class ModelChip extends StatelessWidget {
  const ModelChip({
    required this.model,
    super.key,
    this.version,
    this.dark = false,
  });

  final MetaModel model;
  final String? version;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Palette.brass : const Color(0xFF7A5715);
    final bg = dark
        ? Palette.cream.withValues(alpha: 0.1)
        : Palette.brassSoft.withValues(alpha: 0.8);
    final chip = DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Palette.brass.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(model.icon, size: 13, color: fg),
            const SizedBox(width: 4),
            Text(
              model.label,
              style: context.text.labelSmall?.copyWith(
                color: fg,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
    return Tooltip(
      message: switch (version) {
        null || '' => model.label,
        'mock' => '${model.label} (mock mode)',
        final v => v,
      },
      child: Semantics(label: 'Made by ${model.label}', child: chip),
    );
  }
}

/// A row of model chips plus the latency when the backend reports it.
class AiAttribution extends StatelessWidget {
  const AiAttribution({
    required this.models,
    super.key,
    this.versions = const {},
    this.elapsedMs,
    this.dark = false,
    this.prefix,
  });

  /// Builds from an API `model_versions` map.
  factory AiAttribution.fromVersions(
    Map<String, String> versions, {
    Key? key,
    int? elapsedMs,
    bool dark = false,
    String? prefix,
    List<MetaModel> fallback = const [MetaModel.spark],
  }) {
    final models = MetaModel.from(versions);
    return AiAttribution(
      key: key,
      models: models.isEmpty ? fallback : models,
      versions: versions,
      elapsedMs: elapsedMs,
      dark: dark,
      prefix: prefix,
    );
  }

  final List<MetaModel> models;
  final Map<String, String> versions;
  final int? elapsedMs;
  final bool dark;
  final String? prefix;

  static String formatLatency(int ms) =>
      ms < 1000 ? '$ms ms' : '${(ms / 1000).toStringAsFixed(1)} s';

  @override
  Widget build(BuildContext context) {
    final muted = dark
        ? Palette.cream.withValues(alpha: 0.7)
        : context.colors.onSurfaceVariant;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (prefix != null)
          Text(prefix!, style: context.text.labelSmall?.copyWith(color: muted)),
        for (final m in models)
          ModelChip(model: m, version: versions[m.key], dark: dark),
        if (elapsedMs != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bolt_rounded, size: 14, color: muted),
              Text(
                formatLatency(elapsedMs!),
                key: const ValueKey('ai-latency'),
                style: context.text.labelSmall?.copyWith(
                  color: muted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
      ],
    );
  }
}
