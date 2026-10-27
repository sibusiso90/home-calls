import 'package:fade_call/data/models/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The most recent grading result, kept so the profile card can show the
/// grader's summary (the Barber resource does not carry it).
final gradeResultProvider = NotifierProvider<GradeResultNotifier, GradeResult?>(
  GradeResultNotifier.new,
);

class GradeResultNotifier extends Notifier<GradeResult?> {
  @override
  GradeResult? build() => null;

  void set(GradeResult result) => state = result;
}
