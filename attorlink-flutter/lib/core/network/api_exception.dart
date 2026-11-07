enum ApiErrorKind {
  network,
  timeout,
  unauthorized,
  forbidden,
  notFound,
  conflict,
  validation,
  rateLimited,
  server,
  invalidResponse,
  unsupported,
}

class ApiException implements Exception {
  const ApiException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.fieldErrors = const {},
  });
  final ApiErrorKind kind;
  final String message;
  final int? statusCode;
  final Map<String, String> fieldErrors;

  static ApiErrorKind kindForStatus(int status) => switch (status) {
    400 || 422 => ApiErrorKind.validation,
    401 => ApiErrorKind.unauthorized,
    403 => ApiErrorKind.forbidden,
    404 => ApiErrorKind.notFound,
    409 => ApiErrorKind.conflict,
    429 => ApiErrorKind.rateLimited,
    >= 500 => ApiErrorKind.server,
    _ => ApiErrorKind.invalidResponse,
  };

  static String messageForStatus(int status) => switch (status) {
    400 || 422 => 'Please check the submitted information.',
    401 => 'Please sign in to continue.',
    403 => 'You do not have access to this action.',
    404 => 'The requested information could not be found.',
    409 => 'This action conflicts with the current state. Please refresh.',
    429 => 'Too many requests. Please try again later.',
    >= 500 => 'The service is unavailable. Please try again later.',
    _ => 'The service returned an unexpected response.',
  };

  @override
  String toString() => 'ApiException(${kind.name}, status: $statusCode)';
}
