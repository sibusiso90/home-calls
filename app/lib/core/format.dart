import 'package:intl/intl.dart';

/// Rand with a space as thousands separator: `R385`, `R1 540`.
String rand(int amount) {
  final digits = amount.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return '${amount < 0 ? '-' : ''}R$buffer';
}

String randRange(int min, int max) => '${rand(min)}–${rand(max)}';

final _slot = DateFormat('EEE d MMM, HH:mm');
final _day = DateFormat('EEE d MMM');
final _time = DateFormat('HH:mm');
final _clock = DateFormat('HH:mm:ss');

String formatSlot(DateTime? t) => t == null ? '—' : _slot.format(t.toLocal());
String formatDay(DateTime? t) => t == null ? '—' : _day.format(t.toLocal());
String formatTime(DateTime? t) => t == null ? '—' : _time.format(t.toLocal());
String formatClock(DateTime t) => _clock.format(t.toLocal());

String formatSlotRange(DateTime? start, DateTime? end) {
  if (start == null) return '—';
  if (end == null) return formatSlot(start);
  return '${formatSlot(start)}–${formatTime(end)}';
}

String formatKm(double km) =>
    km < 10 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km';

String formatRating(double? rating) =>
    rating == null ? 'New' : rating.toStringAsFixed(1);

String formatPercent(double? ratio) =>
    ratio == null ? '—' : '${(ratio * 100).round()}%';
