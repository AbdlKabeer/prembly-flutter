import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prembly/prembly.dart';
import 'package:prembly/src/workflow/hosted_flow.dart';

void main() {
  late List<PremblyEvent> events;
  late List<WorkflowResult> results;
  late int closes;
  late HostedFlow flow;

  HostedFlow build(
          {PremblyEventHandler? onEvent, WorkflowCallback? callback}) =>
      HostedFlow(
        product: 'workflow',
        sessionId: 'wf_session_1',
        nonce: 'nonce-1',
        onEvent: onEvent ?? events.add,
        callback: callback ?? results.add,
        onClose: () => closes++,
      );

  setUp(() {
    events = [];
    results = [];
    closes = 0;
    flow = build();
  });

  String message(String type,
          {String nonce = 'nonce-1',
          String product = 'workflow',
          String? node,
          String source = 'prembly-sdk'}) =>
      jsonEncode({
        'n': nonce,
        'd': {
          'source': source,
          'product': product,
          'session_id': 'wf_session_1',
          'type': type,
          if (node != null) 'node_id': node,
        },
      });

  test('passes events on, with the node id on step events', () {
    flow.handleBridgeMessage(message('loaded'));
    flow.handleBridgeMessage(message('step_started', node: 'identity-1'));
    expect(events.map((e) => e.type), ['loaded', 'step_started']);
    expect(events[1].nodeId, 'identity-1');
    expect(events[0].sessionId, 'wf_session_1');
    expect(results, isEmpty);
    expect(closes, 0);
  });

  test('the first end state calls the callback once and closes', () {
    flow.handleBridgeMessage(message('processing'));
    flow.handleBridgeMessage(message('completed'));
    flow.handleBridgeMessage(
        message('failed')); // a second end state is ignored
    expect(results.map((r) => r.status), ['completed']);
    expect(results.single.sessionId, 'wf_session_1');
    expect(closes, 1);
    expect(flow.isClosed, isTrue);
  });

  for (final end in ['completed', 'failed', 'manual_review', 'expired']) {
    test('$end is reported as the callback status', () {
      flow.handleBridgeMessage(message(end));
      expect(results.single.status, end);
    });
  }

  group('what is ignored', () {
    test('a message with the wrong nonce (another page, or a navigated frame)',
        () {
      flow.handleBridgeMessage(message('completed', nonce: 'guessed'));
      expect(events, isEmpty);
      expect(results, isEmpty);
      expect(closes, 0);
    });

    test('a message that is not JSON, or not ours', () {
      flow.handleBridgeMessage('not json');
      flow.handleBridgeMessage(jsonEncode({'n': 'nonce-1', 'd': 'hello'}));
      flow.handleBridgeMessage(jsonEncode({
        'n': 'nonce-1',
        'd': {'source': 'other', 'type': 'completed', 'session_id': 's'}
      }));
      expect(events, isEmpty);
    });

    test('another product', () {
      flow.handleBridgeMessage(message('completed', product: 'kyc'));
      expect(events, isEmpty);
      expect(results, isEmpty);
    });

    test('the legacy source shape is accepted', () {
      flow.handleBridgeMessage(
          message('loaded', source: 'prembly-workflow-sdk'));
      expect(events.single.type, 'loaded');
    });
  });

  group('closing early', () {
    test('is reported once as cancelled, with the last event seen', () {
      flow.handleBridgeMessage(message('step_started', node: 'identity-1'));
      flow.close();
      flow.close(); // closing again does nothing more
      expect(results.single.status, 'cancelled');
      expect(results.single.isCancelled, isTrue);
      expect(results.single.lastEvent, 'step_started');
      expect(results.single.sessionId, 'wf_session_1');
      expect(events.last.type, 'cancelled');
      expect(closes, 1);
    });

    test('processing as the last event means the steps were done', () {
      flow.handleBridgeMessage(message('processing'));
      flow.close();
      expect(results.single.lastEvent, 'processing');
    });

    test('without any event, lastEvent is null', () {
      flow.close();
      expect(results.single.lastEvent, isNull);
    });

    test('after an end state it only cleans up', () {
      flow.handleBridgeMessage(message('completed'));
      flow.close();
      expect(results.map((r) => r.status), ['completed']);
      expect(events.where((e) => e.type == 'cancelled'), isEmpty);
    });

    test('messages after a close are ignored', () {
      flow.close();
      flow.handleBridgeMessage(message('completed'));
      expect(results.map((r) => r.status), ['cancelled']);
    });
  });

  test('a callback or onEvent that throws does not break the flow', () {
    final broken = build(
        onEvent: (_) => throw StateError('boom'),
        callback: (_) => throw StateError('boom'));
    expect(() => broken.handleBridgeMessage(message('completed')),
        returnsNormally);
    expect(broken.isClosed, isTrue);
  });

  test('nonces are random per flow', () {
    final a = HostedFlow(
        product: 'workflow',
        sessionId: 's',
        onEvent: null,
        callback: null,
        onClose: () {});
    final b = HostedFlow(
        product: 'workflow',
        sessionId: 's',
        onEvent: null,
        callback: null,
        onClose: () {});
    expect(a.nonce, isNot(b.nonce));
    expect(a.nonce.length, greaterThanOrEqualTo(24));
  });
}
