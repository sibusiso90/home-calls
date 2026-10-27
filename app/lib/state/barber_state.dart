import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The most recent grading result, kept so the profile card can show the
/// grader's summary (the Barber resource does not carry it).
///
/// Scoped to the signed-in user: signing in as someone else clears it.
final gradeResultProvider = NotifierProvider<GradeResultNotifier, GradeResult?>(
  GradeResultNotifier.new,
);

class GradeResultNotifier extends Notifier<GradeResult?> {
  @override
  GradeResult? build() {
    ref.watch(currentUserIdProvider);
    return null;
  }

  void set(GradeResult result) => state = result;
}
