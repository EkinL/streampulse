import 'dart:math';

final _random = Random.secure();

/// Generates a W3C Trace Context header value (`traceparent`), so a request
/// initiated from the mobile app can be followed as a single distributed
/// trace all the way to the backend and its database queries.
///
/// The app has no local span/tracer, so each request mints its own root
/// trace-id: the mobile leg is not itself visible as a span, but the same
/// trace-id threads through every backend span that handles the request.
String generateTraceparent() {
  final traceId = _randomHex(16);
  final spanId = _randomHex(8);
  return '00-$traceId-$spanId-01';
}

String _randomHex(int byteCount) {
  final bytes = List<int>.generate(byteCount, (_) => _random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
