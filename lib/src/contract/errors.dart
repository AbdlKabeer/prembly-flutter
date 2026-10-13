/// The error codes shared by every Prembly SDK (see docs/contract.md).
enum ErrorCode {
  // HTTP / transport (shared by every product)
  invalidRequest('invalid_request'),
  unauthorised('unauthorised'),
  notFound('not_found'),
  rateLimited('rate_limited'),
  networkError('network_error'),
  timeout('timeout'),
  serverError('server_error'),
  // SDK usage
  invalidKey('invalid_key'),
  notInitialised('not_initialised'),

  /// Anything this SDK, platform or environment does not offer.
  notAvailable('not_available');

  const ErrorCode(this.wire);

  /// The snake_case value used on the wire and in callbacks.
  final String wire;
}

class PremblyError implements Exception {
  PremblyError(this.code, this.message, {this.status, this.details});

  final ErrorCode code;
  final String message;

  /// HTTP status, when the error came from a response.
  final int? status;

  /// Field errors from the API's `errors` object, when present.
  final Object? details;

  @override
  String toString() => 'PremblyError(${code.wire}): $message';
}

/// HTTP status to error code, shared by every product.
ErrorCode errorCodeForStatus(int status) {
  if (status == 401 || status == 403) return ErrorCode.unauthorised;
  if (status == 404) return ErrorCode.notFound;
  if (status == 429) return ErrorCode.rateLimited;
  if (status >= 500) return ErrorCode.serverError;
  return ErrorCode.invalidRequest;
}
