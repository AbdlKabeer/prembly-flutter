import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prembly/prembly.dart';
import 'package:prembly/src/contract/constants.dart';
import 'package:prembly/src/core/config.dart';
import 'package:prembly/src/contract/workflow_types.dart';
import 'package:prembly/src/workflow/workflow_api.dart';
import 'package:prembly/src/workflow/workflow_screen.dart';

class _Handle implements WorkflowHandle {
  @override
  void close() {}
}

ResolvedConfig _config(
        {String hostedUrl = defaultHostedUrl,
        Duration timeout = defaultTimeout}) =>
    ResolvedConfig(
      publishableKey: 'test_pk_abc',
      environment: Environment.sandbox,
      baseUrl: 'https://backend.prembly.com',
      location: false,
      timeout: timeout,
      debug: false,
      hostedUrl: hostedUrl,
    );

const _customer = WorkflowCustomer(
    firstName: 'Ada', lastName: 'Obi', email: 'ada@example.com');

Future<void> _withContext(
    WidgetTester tester, Future<void> Function(BuildContext) body) async {
  late BuildContext context;
  await tester.pumpWidget(Builder(builder: (c) {
    context = c;
    return const SizedBox();
  }));
  await body(context);
}

void main() {
  late List<LaunchOptions> launched;
  late List<WorkflowResult> results;

  WorkflowApi api(http.Client client, {ResolvedConfig? config}) => WorkflowApi(
        getConfig: () => config ?? _config(),
        launcher: (options) {
          launched.add(options);
          return _Handle();
        },
        client: client,
        platform: 'android',
        appId: () async => 'com.example.app',
      );

  setUp(() {
    launched = [];
    results = [];
  });

  http.Response ok() => http.Response(
        jsonEncode({
          'status': true,
          'data': {
            'session_id': 'wf_session_9',
            'link': 'https://hosted.example/?session=wf_session_9'
          },
        }),
        201,
      );

  group('start', () {
    testWidgets(
        'creates a session with the contract headers and body, then opens the link',
        (tester) async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return ok();
      });
      await _withContext(tester, (context) async {
        await api(client).start(
          context: context,
          workflowId: 'wf_123',
          customer: const WorkflowCustomer(
              firstName: 'Ada',
              lastName: 'Obi',
              email: 'ada@example.com',
              phone: '+2348012345678',
              reference: 'ref-1'),
          metadata: {'order': 7},
          redirectUrl: 'https://merchant.example/done',
          callback: results.add,
        );
      });

      expect(seen.method, 'POST');
      expect(seen.url.toString(),
          'https://backend.prembly.com/api/v1/compliance-workflow/sdk/v1/sessions/');
      expect(seen.headers['Content-Type'], startsWith('application/json'));
      expect(seen.headers['X-Publishable-Key'], 'test_pk_abc');
      expect(seen.headers['X-SDK-Platform'], 'android');
      expect(seen.headers['X-SDK-Version'], '0.1.0');
      expect(seen.headers['X-App-Id'], 'com.example.app');
      expect(jsonDecode(seen.body), {
        'workflow_id': 'wf_123',
        'customer': {
          'first_name': 'Ada',
          'last_name': 'Obi',
          'email': 'ada@example.com',
          'phone': '+2348012345678',
          'reference': 'ref-1',
        },
        'metadata': {'order': 7},
        'redirect_url': 'https://merchant.example/done',
      });
      expect(launched.single.sessionId, 'wf_session_9');
      expect(
          launched.single.link, 'https://hosted.example/?session=wf_session_9');
      expect(launched.single.product, 'workflow');
    });

    testWidgets(
        'omits phone, reference and redirect_url when not given; metadata defaults to {}',
        (tester) async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return ok();
      });
      await _withContext(tester, (context) async {
        await api(client)
            .start(context: context, workflowId: 'wf_1', customer: _customer);
      });
      final body = jsonDecode(seen.body) as Map;
      expect(
          (body['customer'] as Map).keys, ['first_name', 'last_name', 'email']);
      expect(body['metadata'], {});
      expect(body.containsKey('redirect_url'), isFalse);
    });

    testWidgets('validates the arguments before any request', (tester) async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        return ok();
      });
      await _withContext(tester, (context) async {
        Future<void> expectInvalid(Future<Object?> Function() call) async {
          await expectLater(
            call(),
            throwsA(isA<PremblyError>()
                .having((e) => e.code, 'code', ErrorCode.invalidRequest)),
          );
        }

        await expectInvalid(() => api(client)
            .start(context: context, workflowId: ' ', customer: _customer));
        await expectInvalid(() => api(client).start(
            context: context,
            workflowId: 'wf',
            customer: const WorkflowCustomer(
                firstName: '', lastName: 'O', email: 'a@b.co')));
        await expectInvalid(() => api(client).start(
            context: context,
            workflowId: 'wf',
            customer: const WorkflowCustomer(
                firstName: 'A', lastName: 'O', email: 'nope')));
      });
      expect(requests, 0);
    });

    for (final (status, code) in [
      (400, ErrorCode.invalidRequest),
      (401, ErrorCode.unauthorised),
      (403, ErrorCode.unauthorised),
      (404, ErrorCode.notFound),
      (429, ErrorCode.rateLimited),
      (500, ErrorCode.serverError),
    ]) {
      testWidgets(
          'HTTP $status is $code, with the API message, and the callback hears failed',
          (tester) async {
        final client = MockClient((_) async => http.Response(
            jsonEncode({
              'status': false,
              'message': 'nope',
              'errors': {'x': 1}
            }),
            status));
        await _withContext(tester, (context) async {
          await expectLater(
            api(client).start(
                context: context,
                workflowId: 'wf',
                customer: _customer,
                callback: results.add),
            throwsA(isA<PremblyError>()
                .having((e) => e.code, 'code', code)
                .having((e) => e.message, 'message', 'nope')
                .having((e) => e.status, 'status', status)
                .having((e) => e.details, 'details', {'x': 1})),
          );
        });
        expect(results.single.status, 'failed');
        expect(results.single.error!.code, code.wire);
        expect(launched, isEmpty);
      });
    }

    testWidgets('an incomplete success body is a server_error', (tester) async {
      final client = MockClient((_) async => http.Response(
          jsonEncode({
            'status': true,
            'data': {'session_id': 'x'}
          }),
          201));
      await _withContext(tester, (context) async {
        await expectLater(
          api(client)
              .start(context: context, workflowId: 'wf', customer: _customer),
          throwsA(isA<PremblyError>()
              .having((e) => e.code, 'code', ErrorCode.serverError)),
        );
      });
    });

    testWidgets('a connection failure is network_error', (tester) async {
      final client =
          MockClient((_) async => throw http.ClientException('offline'));
      await _withContext(tester, (context) async {
        await expectLater(
          api(client).start(
              context: context,
              workflowId: 'wf',
              customer: _customer,
              callback: results.add),
          throwsA(isA<PremblyError>()
              .having((e) => e.code, 'code', ErrorCode.networkError)),
        );
      });
      expect(results.single.status, 'failed');
    });

    testWidgets(
        'before Prembly.init it throws not_initialised and tells the callback',
        (tester) async {
      final uninitialised = WorkflowApi(
        getConfig: () =>
            throw PremblyError(ErrorCode.notInitialised, 'init first'),
        launcher: (_) => _Handle(),
        client: MockClient((_) async => ok()),
        platform: 'ios',
        appId: () async => 'x',
      );
      await _withContext(tester, (context) async {
        await expectLater(
          uninitialised.start(
              context: context,
              workflowId: 'wf',
              customer: _customer,
              callback: results.add),
          throwsA(isA<PremblyError>()
              .having((e) => e.code, 'code', ErrorCode.notInitialised)),
        );
      });
      expect(results.single.status, 'failed');
      expect(results.single.error!.code, 'not_initialised');
    });

    testWidgets('a callback that throws does not hide the real error',
        (tester) async {
      final client = MockClient((_) async => http.Response('{}', 500));
      await _withContext(tester, (context) async {
        await expectLater(
          api(client).start(
              context: context,
              workflowId: 'wf',
              customer: _customer,
              callback: (_) => throw StateError('boom')),
          throwsA(isA<PremblyError>()
              .having((e) => e.code, 'code', ErrorCode.serverError)),
        );
      });
    });
  });

  group('open', () {
    testWidgets('builds the link from the hosted URL', (tester) async {
      await _withContext(tester, (context) async {
        api(MockClient((_) async => ok()))
            .open(context: context, sessionId: 'wf_session_5');
        api(MockClient((_) async => ok())).open(
            context: context,
            sessionId: 'wf_session_5',
            hostedUrl: 'https://other.example/app');
        api(MockClient((_) async => ok())).open(
            context: context,
            sessionId: 'wf_session_5',
            link: 'https://given.example/x');
      });
      expect(launched.map((o) => o.link), [
        'https://sdk-live.prembly.com/?session=wf_session_5',
        'https://other.example/app?session=wf_session_5',
        'https://given.example/x',
      ]);
    });

    testWidgets('needs a session id', (tester) async {
      await _withContext(tester, (context) async {
        expect(
          () => api(MockClient((_) async => ok()))
              .open(context: context, sessionId: ''),
          throwsA(isA<PremblyError>()
              .having((e) => e.code, 'code', ErrorCode.invalidRequest)),
        );
      });
    });
  });

  test('buildHostedLink keeps an existing query and rejects a bad URL', () {
    expect(buildHostedLink('https://h.example/?a=1', 's1'),
        'https://h.example/?a=1&session=s1');
    expect(
        () => buildHostedLink('not a url', 's1'), throwsA(isA<PremblyError>()));
  });

  group('the hosted link', () {
    test(
        'the wrapper page takes the hosted app\'s origin, so the frame runs and its messages arrive',
        () {
      expect(
          wrapperBaseUrlFor(
              Uri.parse('https://sdk-live.prembly.com/?session=x')),
          'https://sdk-live.prembly.com/');
      expect(wrapperBaseUrlFor(Uri.parse('http://localhost:8080/hosted?a=1')),
          'http://localhost:8080/');
    });

    test('must be http(s)', () {
      expect(parseHostedLink('https://sdk-live.prembly.com/?session=x').host,
          'sdk-live.prembly.com');
      expect(parseHostedLink('http://localhost:8080/?session=x').port, 8080);
      for (final bad in [
        'javascript:alert(1)',
        'file:///etc/passwd',
        'ftp://x.example/',
        '/relative',
        'https://'
      ]) {
        expect(() => parseHostedLink(bad), throwsA(isA<PremblyError>()),
            reason: bad);
      }
    });

    test(
        'the wrapper page frames the link, checks origin and source, and carries the nonce',
        () {
      final html = buildWrapperHtml(
          link: Uri.parse('https://sdk-live.prembly.com/?session=wf_1&a=b'),
          nonce: 'N0nce_-x');
      expect(
          html,
          contains(
              '<iframe id="flow" src="https://sdk-live.prembly.com/?session=wf_1&amp;a=b"'));
      expect(
          html,
          contains(
              'allow="camera; microphone; clipboard-read; clipboard-write"'));
      expect(html, contains('var origin = "https://sdk-live.prembly.com";'));
      expect(html, contains('var nonce = "N0nce_-x";'));
      expect(html, contains('event.origin !== origin'));
      expect(html, contains('event.source !== frame.contentWindow'));
      expect(html, contains('PremblyBridge.postMessage'));
      expect(html, isNot(contains("'*'")));
    });

    test('a hostile link cannot break out of the attribute or the script', () {
      final html = buildWrapperHtml(
          link: Uri.parse('https://x.example/?q="><script>alert(1)</script>'),
          nonce: 'n');
      expect(html, isNot(contains('<script>alert(1)')));
      expect('<script>'.allMatches(html).length, 1,
          reason: 'only the wrapper script');
    });
  });
}
