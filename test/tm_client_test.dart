import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prembly/prembly.dart';
import 'package:prembly/src/contract/constants.dart';
import 'package:prembly/src/contract/tm_types.dart';
import 'package:prembly/src/core/config.dart';
import 'package:prembly/src/tm/method_channel_tm_platform.dart';

class _FakePlatform implements TmPlatform {
  _FakePlatform({this.failSignals = false, this.failDeviceId = false});

  final bool failSignals;
  final bool failDeviceId;
  int signalCalls = 0;
  bool? lastIncludeLocation;

  @override
  String get platform => 'ios';

  @override
  Future<String?> getDeviceId() async {
    if (failDeviceId) throw PlatformException(code: 'device_id_failed');
    return 'device-1';
  }

  @override
  Future<SignalBundle> collectSignals(bool includeLocation) async {
    signalCalls++;
    lastIncludeLocation = includeLocation;
    if (failSignals) throw PlatformException(code: 'collect_failed');
    return {
      'device': {'type': 'phone', 'os_name': 'ios'},
      'integrity': {'is_rooted': false},
      'network': {'type': 'wifi'},
      'scam_signals': {'remote_access_app_running': false},
      if (includeLocation) 'location': {'lat': 6.5, 'lng': 3.4},
    };
  }

  @override
  Future<String> getAppId() async => 'com.example.app';
}

ResolvedConfig _config(
        {bool location = false,
        Duration timeout = const Duration(seconds: 5),
        bool debug = false}) =>
    ResolvedConfig(
      publishableKey: 'test_pk_abc',
      environment: Environment.sandbox,
      baseUrl: 'https://backend.prembly.com',
      location: location,
      timeout: timeout,
      debug: debug,
      hostedUrl: defaultHostedUrl,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  late List<http.Request> requests;
  late int counter;

  http.Response sessionResponse(
      {Duration validFor = const Duration(minutes: 15)}) {
    counter++;
    return http.Response(
      jsonEncode({
        'status': true,
        'data': {
          'device_session_id': 'dsess-$counter',
          'device_id': 'device-1',
          'is_known_device': true,
          'expires_at': now.add(validFor).toUtc().toIso8601String(),
        },
      }),
      201,
    );
  }

  TmClient client({
    _FakePlatform? platform,
    Future<http.Response> Function(http.Request)? handler,
    ResolvedConfig? config,
  }) {
    final tm = TmClient(
      platform: platform ?? _FakePlatform(),
      client: MockClient((request) async {
        requests.add(request);
        return handler != null ? await handler(request) : sessionResponse();
      }),
      now: () => now,
    );
    tm.configure(config ?? _config());
    return tm;
  }

  setUp(() {
    now = DateTime.utc(2026, 10, 13, 12);
    requests = [];
    counter = 0;
  });

  test('before init nothing throws: no session, with not_initialised',
      () async {
    final tm = TmClient(
        platform: _FakePlatform(),
        client: MockClient((_) async => sessionResponse()));
    final session = await tm.getDeviceSession();
    expect(session.deviceSessionId, isNull);
    expect(session.error, SessionError.notInitialised);
    expect(requests, isEmpty);
  });

  test('creates a session with the contract headers and body', () async {
    final tm = client();
    tm.identify('customer-123');
    final session = await tm.getDeviceSession();

    expect(session.deviceSessionId, 'dsess-1');
    expect(session.deviceId, 'device-1');
    expect(session.isKnownDevice, isTrue);
    expect(session.isValid, isTrue);

    final request = requests.single;
    expect(request.url.toString(),
        'https://backend.prembly.com/api/v1/fraud/transaction-monitoring/sdk/v1/sessions');
    expect(request.headers['X-Publishable-Key'], 'test_pk_abc');
    expect(request.headers['X-App-Id'], 'com.example.app');
    expect(request.headers['X-SDK-Platform'], 'ios');
    expect(request.headers['X-SDK-Version'], '0.1.0');
    final body = jsonDecode(request.body) as Map;
    expect(body['device'], {'type': 'phone', 'os_name': 'ios'});
    expect(body['device_id'], 'device-1');
    expect(body['customer_id'], 'customer-123');
    expect(body['consent'], {'location': false});
    expect(body.containsKey('location'), isFalse);
    expect(body['collected_at'], '2026-10-13T12:00:00.000Z');
  });

  test('customer_id is only sent once identified, and trimmed', () async {
    final tm = client();
    await tm.getDeviceSession();
    expect(jsonDecode(requests.last.body), isNot(contains('customer_id')));
    tm.identify('  CUST-9  ');
    await tm.getDeviceSession();
    expect((jsonDecode(requests.last.body) as Map)['customer_id'], 'CUST-9');
    tm.identify('   ');
    await tm.getDeviceSession();
    expect(jsonDecode(requests.last.body), isNot(contains('customer_id')));
  });

  group('caching', () {
    test('a session is reused until 30 seconds before it expires', () async {
      final tm = client();
      final first = await tm.getDeviceSession();
      now = now.add(const Duration(minutes: 14));
      expect(
          (await tm.getDeviceSession()).deviceSessionId, first.deviceSessionId);
      expect(requests, hasLength(1));

      now = now.add(const Duration(
          seconds: 31)); // inside the 30 s margin of a 15 min session
      expect((await tm.getDeviceSession()).deviceSessionId,
          isNot(first.deviceSessionId));
      expect(requests, hasLength(2));
    });

    test('forceRefresh makes a new one', () async {
      final tm = client();
      await tm.getDeviceSession();
      await tm.getDeviceSession(forceRefresh: true);
      expect(requests, hasLength(2));
    });

    test('changing the customer drops the cache; the same customer does not',
        () async {
      final tm = client();
      tm.identify('a');
      await tm.getDeviceSession();
      tm.identify('a');
      await tm.getDeviceSession();
      expect(requests, hasLength(1));
      tm.identify('b');
      await tm.getDeviceSession();
      expect(requests, hasLength(2));
    });

    test('reset forgets the customer and the session', () async {
      final tm = client();
      tm.identify('a');
      await tm.getDeviceSession();
      tm.reset();
      await tm.getDeviceSession();
      expect(requests, hasLength(2));
      expect(jsonDecode(requests.last.body), isNot(contains('customer_id')));
    });

    test(
        'turning location on or off drops the cache, and is sent with the signals',
        () async {
      final platform = _FakePlatform();
      final tm = client(platform: platform);
      await tm.getDeviceSession();
      tm.setLocationEnabled(true);
      await tm.getDeviceSession();
      expect(requests, hasLength(2));
      expect(platform.lastIncludeLocation, isTrue);
      final body = jsonDecode(requests.last.body) as Map;
      expect(body['consent'], {'location': true});
      expect(body['location'], {'lat': 6.5, 'lng': 3.4});
      tm.setLocationEnabled(true); // unchanged
      await tm.getDeviceSession();
      expect(requests, hasLength(2));
    });

    test('init again drops the cache', () async {
      final tm = client();
      await tm.getDeviceSession();
      tm.configure(_config());
      await tm.getDeviceSession();
      expect(requests, hasLength(2));
    });

    test('callers at the same moment share one request', () async {
      final gate = Completer<http.Response>();
      final tm = client(handler: (_) => gate.future);
      final a = tm.getDeviceSession();
      final b = tm.getDeviceSession();
      await Future<void>.delayed(Duration.zero);
      gate.complete(sessionResponse());
      final results = await Future.wait([a, b]);
      expect(requests, hasLength(1));
      expect(results[0].deviceSessionId, results[1].deviceSessionId);
    });
  });

  group('it never throws: a failed session is null with a reason', () {
    final cases = <int, SessionError>{
      401: SessionError.unauthorised,
      403: SessionError.unauthorised,
      429: SessionError.rateLimited,
      400: SessionError.rejected,
      422: SessionError.rejected,
      500: SessionError.serverError,
      503: SessionError.serverError,
    };
    cases.forEach((status, error) {
      test('HTTP $status is ${error.wire}', () async {
        final tm = client(handler: (_) async => http.Response('{}', status));
        final session = await tm.getDeviceSession();
        expect(session.deviceSessionId, isNull);
        expect(session.deviceId, 'device-1',
            reason: 'the device ID is still returned');
        expect(session.error, error);
      });
    });

    test('a success with no device_session_id is server_error', () async {
      final tm = client(
          handler: (_) async =>
              http.Response(jsonEncode({'status': true, 'data': {}}), 201));
      expect((await tm.getDeviceSession()).error, SessionError.serverError);
    });

    test('a connection failure is network_error', () async {
      final tm =
          client(handler: (_) async => throw http.ClientException('offline'));
      expect((await tm.getDeviceSession()).error, SessionError.networkError);
    });

    test('a slow server fails open as timeout', () async {
      final tm = client(
        config: _config(timeout: const Duration(milliseconds: 50)),
        handler: (_) => Completer<http.Response>().future,
      );
      expect((await tm.getDeviceSession()).error, SessionError.timeout);
    });

    test(
        'signals that cannot be collected are native_error, and no request is made',
        () async {
      final tm = client(platform: _FakePlatform(failSignals: true));
      final session = await tm.getDeviceSession();
      expect(session.error, SessionError.nativeError);
      expect(session.deviceId, 'device-1');
      expect(requests, isEmpty);
    });

    test('a failed session is not cached: the next call tries again', () async {
      var fail = true;
      final tm = client(
          handler: (_) async =>
              fail ? http.Response('{}', 500) : sessionResponse());
      expect((await tm.getDeviceSession()).deviceSessionId, isNull);
      fail = false;
      expect((await tm.getDeviceSession()).deviceSessionId, isNotNull);
    });
  });

  test('getDeviceId and getSignalsPreview fail to null, not to an exception',
      () async {
    final tm =
        client(platform: _FakePlatform(failDeviceId: true, failSignals: true));
    expect(await tm.getDeviceId(), isNull);
    expect(await tm.getSignalsPreview(), isNull);
    expect(await client().getDeviceId(), 'device-1');
    expect((await client().getSignalsPreview())!.keys,
        containsAll(['device', 'integrity', 'network', 'scam_signals']));
  });

  group('the native bridge', () {
    const channel = MethodChannel('prembly/tm');
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'getDeviceId':
            return 'native-device-id';
          case 'collectSignals':
            return jsonEncode({
              'device': {'type': 'phone'}
            });
          case 'getAppInfo':
            return jsonEncode({
              'appId': 'com.native.app',
              'appVersion': '1',
              'appBuild': '1'
            });
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('reads the device id, the signals (JSON) and the app id', () async {
      final platform = MethodChannelTmPlatform();
      expect(await platform.getDeviceId(), 'native-device-id');
      expect(await platform.collectSignals(true), {
        'device': {'type': 'phone'}
      });
      expect(calls.last.arguments, {'includeLocation': true});
      expect(await platform.getAppId(), 'com.native.app');
    });

    test(
        'a missing app id is "unknown", and a bad signals reply throws (so TM reports native_error)',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => null);
      final platform = MethodChannelTmPlatform();
      expect(await platform.getAppId(), 'unknown');
      await expectLater(
          platform.collectSignals(false), throwsA(isA<FormatException>()));
    });
  });
}
