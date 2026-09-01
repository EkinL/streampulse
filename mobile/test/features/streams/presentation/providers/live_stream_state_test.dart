import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/features/streams/presentation/providers/live_stream_provider.dart';

void main() {
  group('LiveStreamState', () {
    test('les valeurs par defaut sont deconnectees et pretes a ecouter', () {
      const state = LiveStreamState();

      expect(state.streamId, isNull);
      expect(state.isConnected, isFalse);
      expect(state.isConnecting, isFalse);
      expect(state.isReceivingData, isFalse);
      expect(state.bytesReceived, 0);
      expect(state.statusText, 'Tap play to listen');
    });

    test('copyWith sans argument conserve les valeurs', () {
      const state = LiveStreamState(
        streamId: 's1',
        isConnected: true,
        bytesReceived: 42,
        statusText: 'Playing',
      );

      final copy = state.copyWith();

      expect(copy.streamId, 's1');
      expect(copy.isConnected, isTrue);
      expect(copy.bytesReceived, 42);
      expect(copy.statusText, 'Playing');
    });

    test('copyWith ne modifie que les champs fournis', () {
      const state = LiveStreamState(streamId: 's1', statusText: 'Connecting...');

      final copy = state.copyWith(isConnected: true, statusText: 'Connected');

      expect(copy.streamId, 's1');
      expect(copy.isConnected, isTrue);
      expect(copy.statusText, 'Connected');
    });
  });
}
