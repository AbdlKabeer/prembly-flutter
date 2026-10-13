// Runs the real plugin on a device or simulator:
//   cd example && flutter test integration_test -d <device>
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prembly/prembly.dart';

/// The signal keys prembly-tm-native sends today (its contract/signals.contract.json), per platform.
const Map<String, Map<String, List<String>>> _signalContract = {
  'ios': {
    'device': [
      'type',
      'model',
      'manufacturer',
      'os_name',
      'os_version',
      'app_version',
      'app_build',
      'locale',
      'timezone',
    ],
    'integrity': [
      'is_rooted',
      'is_emulator',
      'is_debugger_attached',
      'is_device_secure',
    ],
    'network': ['type', 'is_vpn_active', 'is_proxy_configured'],
    'scam_signals': [
      'is_screen_shared_or_recorded',
      'remote_access_app_running',
    ],
  },
  'android': {
    'device': [
      'type',
      'model',
      'manufacturer',
      'os_name',
      'os_version',
      'app_version',
      'app_build',
      'locale',
      'timezone',
    ],
    'integrity': [
      'is_rooted',
      'is_emulator',
      'is_debugger_attached',
      'developer_options_enabled',
      'usb_debugging_enabled',
      'is_device_secure',
    ],
    'network': ['type', 'is_vpn_active', 'is_proxy_configured'],
    'scam_signals': [
      'is_screen_shared_or_recorded',
      'remote_access_app_running',
      'remote_access_app_installed',
    ],
  },
};

/// A stand-in for the hosted workflow app and the Prembly API, on this machine.
class _FakeBackend {
  _FakeBackend._(this._server);

  final HttpServer _server;
  final List<Map<String, Object?>> tmRequests = [];
  final List<String> hostedRequests = [];

  static Future<_FakeBackend> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final backend = _FakeBackend._(server);
    server.listen(backend._handle);
    return backend;
  }

  String get origin => 'http://127.0.0.1:${_server.port}';

  Future<void> stop() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    if (request.method == 'POST' &&
        request.uri.path.endsWith('/transaction-monitoring/sdk/v1/sessions')) {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      tmRequests.add({
        'headers': {
          for (final h in [
            'x-publishable-key',
            'x-app-id',
            'x-sdk-platform',
            'x-sdk-version',
          ])
            h: request.headers.value(h),
        },
        'body': body,
      });
      request.response
        ..statusCode = 201
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'status': true,
            'data': {
              'device_session_id': 'dsess-${tmRequests.length}',
              'device_id': body['device_id'],
              'is_known_device': false,
              'expires_at': DateTime.now()
                  .toUtc()
                  .add(const Duration(minutes: 15))
                  .toIso8601String(),
            },
          }),
        );
    } else if (request.uri.path == '/hosted') {
      hostedRequests.add(
        '${request.uri} referer=${request.headers.value('referer')} ua=${request.headers.value('user-agent')}',
      );
      request.response
        ..headers.contentType = ContentType.html
        ..write(
          _hostedPage(request.uri.queryParameters['scenario'] ?? 'complete'),
        );
    } else {
      request.response.statusCode = 404;
    }
    await request.response.close();
  }

  String _hostedPage(String scenario) =>
      '''<!doctype html><html><body><p>hosted app: $scenario</p>
<script>
  var sid = new URLSearchParams(location.search).get('session');
  function emit(type, node) {
    var m = { source: 'prembly-sdk', product: 'workflow', session_id: sid, type: type };
    if (node) m.node_id = node;
    parent.postMessage(m, '*');
  }
  var scenario = '$scenario';
  if (scenario === 'complete') {
    setTimeout(function () { emit('loaded'); }, 300);
    setTimeout(function () { emit('step_started', 'identity-1'); }, 600);
    setTimeout(function () { emit('step_completed', 'identity-1'); }, 900);
    setTimeout(function () { emit('processing'); }, 1200);
    setTimeout(function () { emit('completed'); }, 1500);
  } else if (scenario === 'cancel') {
    setTimeout(function () { emit('loaded'); }, 300);
    setTimeout(function () { emit('step_started', 'identity-1'); }, 600);
  } else if (scenario === 'spoof') {
    // A page in the frame tries to report a result by calling the native bridge directly (the frame
    // shares the wrapper page's origin, so it can reach it), with a guessed nonce and with none.
    setTimeout(function () {
      var forged = { source: 'prembly-sdk', product: 'workflow', session_id: sid, type: 'completed' };
      try { parent.PremblyBridge.postMessage(JSON.stringify({ n: 'guess', d: forged })); } catch (e) {}
      try { parent.PremblyBridge.postMessage(JSON.stringify({ d: forged })); } catch (e) {}
      try { parent.PremblyBridge.postMessage('completed'); } catch (e) {}
      emit('loaded');
    }, 300);
  }
</script></body></html>''';
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 20),
  List<String> Function()? diagnostics,
}) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) {
      fail('timed out waiting. ${diagnostics?.call().join(' | ')}');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late _FakeBackend backend;

  setUpAll(() async => backend = await _FakeBackend.start());
  tearDownAll(() => backend.stop());

  group('Transaction Monitoring on the device', () {
    testWidgets('the native signals have exactly the contract keys', (
      tester,
    ) async {
      Prembly.init(
        publishableKey: 'test_pk_integration',
        baseUrl: backend.origin,
      );
      final signals = await Prembly.tm.getSignalsPreview();
      expect(signals, isNotNull);

      final platform = Platform.isIOS ? 'ios' : 'android';
      _signalContract[platform]!.forEach((section, keys) {
        final actual = (signals![section] as Map).keys.toList()..sort();
        expect(
          actual,
          (List<String>.of(keys)..sort()),
          reason: '$section keys',
        );
      });
      expect(
        signals!.containsKey('location'),
        isFalse,
        reason: 'location is off by default',
      );

      final device = signals['device'] as Map;
      expect(device['os_name'], platform);
      expect(device['manufacturer'], isNotEmpty);
      expect(device['timezone'], isNotEmpty);
      final integrity = signals['integrity'] as Map;
      expect(
        integrity['is_emulator'],
        isTrue,
        reason: 'this runs on a simulator or emulator',
      );
      expect(integrity['is_rooted'], isFalse);
    });

    testWidgets('the device id is stable and looks like a UUID', (
      tester,
    ) async {
      Prembly.init(
        publishableKey: 'test_pk_integration',
        baseUrl: backend.origin,
      );
      final first = await Prembly.tm.getDeviceId();
      final second = await Prembly.tm.getDeviceId();
      expect(first, isNotNull);
      expect(first, second);
      expect(
        first,
        matches(
          RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
          ),
        ),
      );
    });

    testWidgets('a device session is created once and then cached', (
      tester,
    ) async {
      backend.tmRequests.clear();
      Prembly.init(
        publishableKey: 'test_pk_integration',
        baseUrl: backend.origin,
      );
      Prembly.tm.identify('customer-42');

      final session = await Prembly.tm.getDeviceSession();
      expect(session.deviceSessionId, 'dsess-1');
      expect(session.error, isNull);
      expect((await Prembly.tm.getDeviceSession()).deviceSessionId, 'dsess-1');
      expect(backend.tmRequests, hasLength(1));

      final request = backend.tmRequests.single;
      final headers = request['headers'] as Map;
      expect(headers['x-publishable-key'], 'test_pk_integration');
      expect(headers['x-sdk-platform'], Platform.isIOS ? 'ios' : 'android');
      expect(headers['x-sdk-version'], Prembly.version);
      expect(headers['x-app-id'], isNotEmpty);
      expect(headers['x-app-id'], isNot('unknown'));
      final body = request['body'] as Map;
      expect(body['customer_id'], 'customer-42');
      expect(body['device_id'], session.deviceId);
      expect(
        (body['device'] as Map)['os_name'],
        Platform.isIOS ? 'ios' : 'android',
      );
      expect(body['consent'], {'location': false});
    });

    testWidgets('an unreachable backend fails open', (tester) async {
      Prembly.init(
        publishableKey: 'test_pk_integration',
        baseUrl: 'http://127.0.0.1:1',
        timeout: const Duration(seconds: 3),
      );
      final session = await Prembly.tm.getDeviceSession();
      expect(session.deviceSessionId, isNull);
      expect(session.error, SessionError.networkError);
      expect(session.deviceId, isNotNull);
    });
  });

  group('a hosted workflow in the WebView', () {
    late List<PremblyEvent> events;
    late List<WorkflowResult> results;

    Future<void> openFlow(WidgetTester tester, String scenario) async {
      events = [];
      results = [];
      Prembly.init(
        publishableKey: 'test_pk_integration',
        baseUrl: backend.origin,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Prembly.workflow.open(
                    context: context,
                    sessionId: 'wf_session_it',
                    link:
                        '${backend.origin}/hosted?scenario=$scenario&session=wf_session_it',
                    onEvent: events.add,
                    callback: results.add,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets(
      'events come through, the end state calls back once, and the screen closes',
      (tester) async {
        await openFlow(tester, 'complete');
        expect(
          find.byTooltip('Close'),
          findsOneWidget,
          reason: 'the flow screen is showing',
        );

        await _pumpUntil(
          tester,
          () => results.isNotEmpty,
          diagnostics: () => [
            'hosted hits: ${backend.hostedRequests}',
            'events: $events',
          ],
        );
        expect(events.map((e) => e.type), [
          'loaded',
          'step_started',
          'step_completed',
          'processing',
          'completed',
        ]);
        expect(events[1].nodeId, 'identity-1');
        expect(
          events.every(
            (e) => e.sessionId == 'wf_session_it' && e.product == 'workflow',
          ),
          isTrue,
        );
        expect(results.single.status, 'completed');
        expect(results.single.sessionId, 'wf_session_it');

        await tester.pump(const Duration(milliseconds: 500));
        expect(
          find.byTooltip('Close'),
          findsNothing,
          reason: 'the screen closed itself',
        );
      },
    );

    testWidgets(
      'closing early is reported once as cancelled, with the last event',
      (tester) async {
        await openFlow(tester, 'cancel');
        await _pumpUntil(
          tester,
          () => events.any((e) => e.type == 'step_started'),
        );

        await tester.tap(find.byTooltip('Close'));
        await tester.pump(const Duration(milliseconds: 500));

        expect(results.single.status, 'cancelled');
        expect(results.single.lastEvent, 'step_started');
        expect(events.last.type, 'cancelled');
        expect(find.byTooltip('Close'), findsNothing);
      },
    );

    testWidgets(
      'a page in the frame cannot fake a result through the native bridge',
      (tester) async {
        await openFlow(tester, 'spoof');
        await _pumpUntil(tester, () => events.any((e) => e.type == 'loaded'));
        await tester.pump(const Duration(seconds: 1));

        expect(
          results,
          isEmpty,
          reason: 'the forged "completed" messages were ignored',
        );
        expect(events.map((e) => e.type), ['loaded']);

        await tester.tap(find.byTooltip('Close'));
        await tester.pump(const Duration(milliseconds: 500));
        expect(results.single.status, 'cancelled');
        expect(results.single.lastEvent, 'loaded');
      },
    );
  });
}
