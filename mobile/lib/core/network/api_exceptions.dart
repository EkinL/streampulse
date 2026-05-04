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
    String message = 'Unauthorized. Please log in again.',
  }) : super(message: message, statusCode: 401);
}

class NotFoundException extends ApiException {
  const NotFoundException({
    String message = 'Resource not found.',
  }) : super(message: message, statusCode: 404);
}

class ServerException extends ApiException {
  const ServerException({
    String message = 'An internal server error occurred.',
  }) : super(message: message, statusCode: 500);
}
