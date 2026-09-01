import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/core/storage/token_store_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  late IoTokenStore store;

  setUp(() {
    calls.clear();
    store = IoTokenStore();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'read':
          return 'stored-value';
        default:
          return null;
      }
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('createTokenStore renvoie un IoTokenStore', () {
    expect(createTokenStore(), isA<IoTokenStore>());
  });

  test('write transmet la cle et la valeur au canal natif', () async {
    await store.write('access_token', 'abc');

    expect(calls.single.method, 'write');
    final args = calls.single.arguments as Map;
    expect(args['key'], 'access_token');
    expect(args['value'], 'abc');
  });

  test('read renvoie la valeur du canal natif', () async {
    final value = await store.read('access_token');

    expect(value, 'stored-value');
    expect(calls.single.method, 'read');
    expect((calls.single.arguments as Map)['key'], 'access_token');
  });

  test('read renvoie null si le canal natif echoue', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'error', message: 'keychain unavailable');
    });

    final value = await store.read('access_token');

    expect(value, isNull);
  });

  test('delete transmet la cle au canal natif', () async {
    await store.delete('access_token');

    expect(calls.single.method, 'delete');
    expect((calls.single.arguments as Map)['key'], 'access_token');
  });
}
