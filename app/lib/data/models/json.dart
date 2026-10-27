/// Small helpers for reading the contract's snake_case JSON safely.
typedef Json = Map<String, dynamic>;

extension JsonRead on Json {
  String str(String key) => this[key] as String;
  String? strOrNull(String key) => this[key] as String?;
  int integer(String key) => (this[key] as num).toInt();
  int? intOrNull(String key) => (this[key] as num?)?.toInt();
  double dbl(String key) => (this[key] as num).toDouble();
  double? dblOrNull(String key) => (this[key] as num?)?.toDouble();
  bool flag(String key, {bool fallback = false}) =>
      this[key] as bool? ?? fallback;
  Json obj(String key) => (this[key] as Map).cast<String, dynamic>();
  Json? objOrNull(String key) => (this[key] as Map?)?.cast<String, dynamic>();
  List<String> strings(String key) =>
      ((this[key] as List?) ?? const []).cast<String>().toList();
  List<T> list<T>(String key, T Function(Json json) parse) =>
      ((this[key] as List?) ?? const [])
          .map((e) => parse((e as Map).cast<String, dynamic>()))
          .toList();
  DateTime? timeOrNull(String key) {
    final v = this[key] as String?;
    return v == null ? null : DateTime.parse(v);
  }

  Map<String, String> stringMap(String key) => ((this[key] as Map?) ?? const {})
      .map((k, v) => MapEntry(k as String, '$v'));
}

/// Formats a local [DateTime] as ISO 8601 with its UTC offset, e.g.
/// `2026-10-28T16:02:11+02:00`, as the contract expects.
String isoWithOffset(DateTime time) {
  final local = time.toLocal();
  final offset = local.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final abs = offset.abs();
  String two(int n) => n.toString().padLeft(2, '0');
  final base = local.toIso8601String().split('.').first;
  return '$base$sign${two(abs.inHours)}:${two(abs.inMinutes % 60)}';
}
