import 'package:fade_call/core/format.dart';
import 'package:fade_call/core/theme.dart';
import 'package:flutter/material.dart';

/// Day chips (Today, Tomorrow, …) over the free times for the chosen day.
class SlotPicker extends StatefulWidget {
  const SlotPicker({
    required this.slots,
    required this.selected,
    required this.onSelected,
    super.key,
    this.now,
  });

  final List<DateTime> slots;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelected;

  /// For tests; defaults to the clock.
  final DateTime? now;

  @override
  State<SlotPicker> createState() => _SlotPickerState();
}

class _SlotPickerState extends State<SlotPicker> {
  DateTime? _day;

  static DateTime _dateOf(DateTime t) {
    final l = t.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  Map<DateTime, List<DateTime>> get _byDay {
    final out = <DateTime, List<DateTime>>{};
    for (final s in widget.slots) {
      (out[_dateOf(s)] ??= []).add(s);
    }
    return out;
  }

  String _dayLabel(DateTime day) {
    final today = _dateOf(widget.now ?? DateTime.now());
    return switch (day.difference(today).inDays) {
      0 => 'Today',
      1 => 'Tomorrow',
      _ => formatDay(day),
    };
  }

  @override
  Widget build(BuildContext context) {
    final byDay = _byDay;
    if (byDay.isEmpty) return const SizedBox.shrink();
    final selected = widget.selected;
    final day =
        _day ?? (selected != null ? _dateOf(selected) : byDay.keys.first);
    final times = byDay[day] ?? byDay.values.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final d in byDay.keys) ...[
                ChoiceChip(
                  key: ValueKey('slot-day-${d.toIso8601String()}'),
                  label: Text(_dayLabel(d)),
                  selected: d == day,
                  onSelected: (_) => setState(() => _day = d),
                ),
                const SizedBox(width: Gap.sm),
              ],
            ],
          ),
        ),
        const SizedBox(height: Gap.sm + 4),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            for (final t in times)
              ChoiceChip(
                label: Text(formatTime(t)),
                selected: t == selected,
                onSelected: (_) => widget.onSelected(t),
              ),
          ],
        ),
      ],
    );
  }
}
