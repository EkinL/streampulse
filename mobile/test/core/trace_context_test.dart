import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/core/network/trace_context.dart';

void main() {
  group('generateTraceparent', () {
    final format = RegExp(r'^00-[0-9a-f]{32}-[0-9a-f]{16}-01$');

    test('matches the W3C traceparent format', () {
      expect(generateTraceparent(), matches(format));
    });

    test('trace-id and span-id are not all zeros', () {
      final parts = generateTraceparent().split('-');
      expect(parts[1], isNot('0' * 32));
      expect(parts[2], isNot('0' * 16));
    });

    test('generates a fresh trace-id on every call', () {
      final first = generateTraceparent();
      final second = generateTraceparent();
      expect(first, isNot(equals(second)));
    });
  });
}
