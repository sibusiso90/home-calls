import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/data/upload_file.dart';
import 'package:fade_call/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The client's in-progress quote: inputs and the request's outcome.
final class QuoteDraft {
  const QuoteDraft({
    this.areaId,
    this.selfie,
    this.reference,
    this.result,
    this.startedAt,
  });

  final String? areaId;
  final UploadFile? selfie;
  final UploadFile? reference;

  /// Null before submit; loading, data or error after.
  final AsyncValue<Quote>? result;
  final DateTime? startedAt;

  bool get ready => areaId != null && selfie != null && reference != null;
  bool get submitting => result?.isLoading ?? false;
  Quote? get quote => result?.value;
}

final quoteControllerProvider = NotifierProvider<QuoteController, QuoteDraft>(
  QuoteController.new,
);

class QuoteController extends Notifier<QuoteDraft> {
  @override
  QuoteDraft build() {
    ref.watch(currentUserIdProvider);
    return const QuoteDraft();
  }

  void setArea(String? id) => state = QuoteDraft(
    areaId: id,
    selfie: state.selfie,
    reference: state.reference,
  );

  void setSelfie(UploadFile file) => state = QuoteDraft(
    areaId: state.areaId,
    selfie: file,
    reference: state.reference,
  );

  void setReference(UploadFile file) => state = QuoteDraft(
    areaId: state.areaId,
    selfie: state.selfie,
    reference: file,
  );

  Future<void> submit() async {
    final s = state;
    if (!s.ready || s.submitting) return;
    state = QuoteDraft(
      areaId: s.areaId,
      selfie: s.selfie,
      reference: s.reference,
      result: const AsyncLoading(),
      startedAt: DateTime.now(),
    );
    final result = await AsyncValue.guard(
      () => ref
          .read(apiProvider)
          .createQuote(
            selfie: s.selfie!,
            reference: s.reference!,
            areaId: s.areaId!,
          ),
    );
    if (!ref.mounted) return;
    state = QuoteDraft(
      areaId: s.areaId,
      selfie: s.selfie,
      reference: s.reference,
      result: result,
      startedAt: state.startedAt,
    );
  }

  /// Refetches the quote to get fresh signed image URLs (they expire).
  Future<void> refreshUrls() async {
    final current = state.quote;
    if (current == null) return;
    try {
      final fresh = await ref.read(apiProvider).quote(current.id);
      if (!ref.mounted || state.quote?.id != current.id) return;
      state = QuoteDraft(
        areaId: state.areaId,
        selfie: state.selfie,
        reference: state.reference,
        result: AsyncData(fresh),
        startedAt: state.startedAt,
      );
    } on Object {
      // Keep showing the placeholder; the user can try again.
    }
  }

  /// Back to the form with the same inputs (after an error).
  void editInputs() => state = QuoteDraft(
    areaId: state.areaId,
    selfie: state.selfie,
    reference: state.reference,
  );

  void reset() => state = QuoteDraft(areaId: state.areaId);
}
