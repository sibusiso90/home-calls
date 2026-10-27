/// A typed error mapped from the contract's error envelope:
/// `{"error": {"code": "...", "message": "..."}}`.
final class ApiException implements Exception {
  const ApiException(this.code, this.message, {this.statusCode});

  /// Used when the request never reached the server.
  const ApiException.network([String? detail])
    : code = 'network',
      message =
          detail ??
          "We couldn't reach Fade Call. Check your connection and try again.",
      statusCode = null;

  final String code;
  final String message;
  final int? statusCode;

  bool get isUnauthorized => code == 'unauthorized' || statusCode == 401;
  bool get isVerdictRequired => code == 'verdict_required';
  bool get isConflict => code == 'conflict';

  @override
  String toString() => 'ApiException($code): $message';
}

/// Plain-language message for any error shown to a user.
String friendlyError(Object error) => switch (error) {
  ApiException(:final message) => message,
  _ => 'Something went wrong. Please try again.',
};
