import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prembly/prembly.dart';
import 'package:prembly/src/contract/errors.dart';
import 'package:prembly/src/contract/events.dart';
import 'package:prembly/src/contract/keys.dart';
import 'package:prembly/src/version.dart';

void main() {
  group('publishable keys', () {
    test('live_pk_ is live and test_pk_ is sandbox', () {
      expect(parsePublishableKey('live_pk_abc').environment, Environment.live);
      expect(
          parsePublishableKey('test_pk_abc').environment, Environment.sandbox);
      expect(
          parsePublishableKey('  test_pk_abc  ').publishableKey, 'test_pk_abc');
    });

    test('everything else is rejected, including secret keys', () {
      for (final bad in [
        'live_sk_abc',
        'test_sk_abc',
        'pk_live_abc',
        '',
        '   ',
        null,
        42
      ]) {
        expect(
          () => parsePublishableKey(bad),
          throwsA(isA<PremblyError>()
              .having((e) => e.code, 'code', ErrorCode.invalidKey)),
          reason: 'input: $bad',
        );
      }
    });

    test('Prembly.init throws on a secret key and names the fix', () {
      expect(
        () => Prembly.init(publishableKey: 'live_sk_abc'),
        throwsA(isA<PremblyError>()
            .having((e) => e.message, 'message', contains('public key'))),
      );
    });
  });

  group('error codes', () {
    test('HTTP statuses map as the contract says', () {
      expect(errorCodeForStatus(400), ErrorCode.invalidRequest);
      expect(errorCodeForStatus(422), ErrorCode.invalidRequest);
      expect(errorCodeForStatus(401), ErrorCode.unauthorised);
      expect(errorCodeForStatus(403), ErrorCode.unauthorised);
      expect(errorCodeForStatus(404), ErrorCode.notFound);
      expect(errorCodeForStatus(429), ErrorCode.rateLimited);
      expect(errorCodeForStatus(500), ErrorCode.serverError);
      expect(errorCodeForStatus(503), ErrorCode.serverError);
    });

    test('wire values are the contract snake_case codes', () {
      expect(
        ErrorCode.values.map((c) => c.wire),
        containsAll([
          'invalid_request',
          'unauthorised',
          'not_found',
          'rate_limited',
          'network_error',
          'timeout',
          'server_error',
          'invalid_key',
          'not_initialised',
          'not_available',
        ]),
      );
    });
  });

  group('event envelopes', () {
    Map<String, Object?> envelope(
            {String source = 'prembly-sdk', String type = 'completed'}) =>
        {
          'source': source,
          'product': 'workflow',
          'session_id': 'wf_session_1',
          'type': type,
        };

    test('accepts the new envelope', () {
      final e = normaliseEnvelope({...envelope(), 'node_id': 'identity-1'})!;
      expect(e.product, 'workflow');
      expect(e.sessionId, 'wf_session_1');
      expect(e.type, 'completed');
      expect(e.nodeId, 'identity-1');
    });

    test('accepts the legacy shape and defaults the product to workflow', () {
      final e = normaliseEnvelope({
        'source': 'prembly-workflow-sdk',
        'type': 'loaded',
        'session_id': 's'
      })!;
      expect(e.product, 'workflow');
      expect(e.nodeId, isNull);
    });

    test('rejects anything that is not ours', () {
      expect(normaliseEnvelope(null), isNull);
      expect(normaliseEnvelope('x'), isNull);
      expect(normaliseEnvelope(envelope(source: 'someone-else')), isNull);
      expect(
          normaliseEnvelope({
            'source': 'prembly-sdk',
            'type': 'completed',
            'session_id': 's'
          }),
          isNull,
          reason: 'no product');
      expect(
          normaliseEnvelope({
            'source': 'prembly-sdk',
            'product': 'workflow',
            'type': 'completed'
          }),
          isNull,
          reason: 'no session');
      expect(normaliseEnvelope(envelope(type: 'made_up')), isNull,
          reason: 'unknown workflow type');
    });

    test('terminal types are completed, failed, manual_review and expired', () {
      for (final t in ['completed', 'failed', 'manual_review', 'expired']) {
        expect(isTerminalType(t), isTrue);
      }
      for (final t in [
        'loaded',
        'step_started',
        'step_completed',
        'processing',
        'cancelled'
      ]) {
        expect(isTerminalType(t), isFalse);
      }
    });
  });

  test('the version header equals pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match =
        RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)!;
    expect(sdkVersion, match.group(1));
  });
}
