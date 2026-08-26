class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic data;

  const ApiException({
    required this.message,
    this.statusCode,
    this.data,
  });

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class UnauthorizedException extends ApiException {
  const UnauthorizedException({
    super.message = 'Unauthorized. Please log in again.',
  }) : super(statusCode: 401);
}

class NotFoundException extends ApiException {
  const NotFoundException({
    super.message = 'Resource not found.',
  }) : super(statusCode: 404);
}

class ServerException extends ApiException {
  const ServerException({
    super.message = 'An internal server error occurred.',
  }) : super(statusCode: 500);
}
