import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/data/upload_file.dart';
import 'package:fade_call/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How the client tells us which cut they want.
enum CutChoice {
  /// Pick a cut from the catalog.
  catalog,

  /// Send a reference photo of a specific cut.
  photo,

  /// Let Muse Spark pick the cut that suits their face.
  suggest,
}

/// The client's in-progress quote: inputs and the request's outcome.
final class QuoteDraft {
  const QuoteDraft({
    this.areaId,
    this.selfie,
    this.choice = CutChoice.catalog,
    this.cutId,
    this.reference,
    this.result,
    this.startedAt,
  });

  final String? areaId;
  final UploadFile? selfie;
  final CutChoice choice;
  final String? cutId;
  final UploadFile? reference;

  /// Null before submit; loading, data or error after.
  final AsyncValue<Quote>? result;
  final DateTime? startedAt;

  bool get cutReady => switch (choice) {
    CutChoice.catalog => cutId != null,
    CutChoice.photo => reference != null,
    CutChoice.suggest => true,
  };
  bool get ready => areaId != null && selfie != null && cutReady;
  bool get submitting => result?.isLoading ?? false;
  Quote? get quote => result?.value;

  /// The same inputs with no result (back to the form).
  QuoteDraft inputs({
    String? areaId,
    UploadFile? selfie,
    CutChoice? choice,
    String? cutId,
    UploadFile? reference,
  }) => QuoteDraft(
    areaId: areaId ?? this.areaId,
    selfie: selfie ?? this.selfie,
    choice: choice ?? this.choice,
    cutId: cutId ?? this.cutId,
    reference: reference ?? this.reference,
  );

  QuoteDraft withResult(AsyncValue<Quote> result, {DateTime? startedAt}) =>
      QuoteDraft(
        areaId: areaId,
        selfie: selfie,
        choice: choice,
        cutId: cutId,
        reference: reference,
        result: result,
        startedAt: startedAt ?? this.startedAt,
      );
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
    choice: state.choice,
    cutId: state.cutId,
    reference: state.reference,
  );

  void setSelfie(UploadFile file) => state = state.inputs(selfie: file);

  void setChoice(CutChoice choice) => state = state.inputs(choice: choice);

  void setCut(String cutId) => state = state.inputs(cutId: cutId);

  void setReference(UploadFile file) => state = state.inputs(reference: file);

  Future<void> submit() async {
    final s = state;
    if (!s.ready || s.submitting) return;
    state = s.withResult(const AsyncLoading(), startedAt: DateTime.now());
    final result = await AsyncValue.guard(
      () => ref
          .read(apiProvider)
          .createQuote(
            selfie: s.selfie!,
            areaId: s.areaId!,
            reference: s.choice == CutChoice.photo ? s.reference : null,
            cutId: s.choice == CutChoice.catalog ? s.cutId : null,
          ),
    );
    if (!ref.mounted) return;
    state = s.withResult(result, startedAt: state.startedAt);
  }

  /// Quotes a suggested cut instead, with the same selfie.
  Future<void> requote(String cutId) async {
    final current = state.quote;
    if (current == null || state.submitting) return;
    final s = state.inputs(choice: CutChoice.catalog, cutId: cutId);
    state = s.withResult(const AsyncLoading(), startedAt: DateTime.now());
    final result = await AsyncValue.guard(
      () => ref.read(apiProvider).requote(current.id, cutId),
    );
    if (!ref.mounted) return;
    state = s.withResult(result, startedAt: state.startedAt);
  }

  /// Refetches the quote to get fresh signed image URLs (they expire).
  Future<void> refreshUrls() async {
    final current = state.quote;
    if (current == null) return;
    try {
      final fresh = await ref.read(apiProvider).quote(current.id);
      if (!ref.mounted || state.quote?.id != current.id) return;
      state = state.withResult(AsyncData(fresh));
    } on Object {
      // Keep showing the placeholder; the user can try again.
    }
  }

  /// Back to the form with the same inputs (after an error).
  void editInputs() => state = state.inputs();

  void reset() => state = QuoteDraft(areaId: state.areaId);
}
