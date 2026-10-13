import 'dart:convert';
import 'dart:math';

import '../contract/events.dart';
import '../contract/workflow_types.dart';

/// The state of one hosted flow (a workflow shown in a WebView): which events reach the app, when
/// the flow has ended, and what closing early means. It has no UI, so it can be tested on its own.
///
/// The rules are the web launcher's:
/// * a message is accepted only if it is one of ours, for this product, and carries this flow's nonce
///   (the nonce is the Flutter stand-in for the web's origin + source-window check);
/// * the first end state wins, and the callback fires once;
/// * closing before an end state is reported once as `cancelled`, with the last event seen.
class HostedFlow implements WorkflowHandle {
  HostedFlow({
    required this.product,
    required this.sessionId,
    required this.onEvent,
    required this.callback,
    required void Function() onClose,
    String? nonce,
  })  : nonce = nonce ?? _newNonce(),
        _onClose = onClose;

  final String product;
  final String sessionId;
  final PremblyEventHandler? onEvent;
  final WorkflowCallback? callback;
  final void Function() _onClose;

  /// Shared with the wrapper page. A page the hosted app navigates to cannot read it.
  final String nonce;

  bool _closed = false;
  bool _finished = false;
  String? _lastEvent;

  bool get isClosed => _closed;
  bool get isFinished => _finished;

  static String _newNonce() {
    final random = Random.secure();
    return base64UrlEncode(List<int>.generate(18, (_) => random.nextInt(256)));
  }

  /// Handles a message from the wrapper page: `{"n": nonce, "d": <hosted app's message>}`.
  void handleBridgeMessage(String raw) {
    if (_closed || _finished) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (decoded is! Map || decoded['n'] != nonce) return;

    final envelope = normaliseEnvelope(decoded['d']);
    if (envelope == null || envelope.product != product) return;

    final terminal = isTerminalType(envelope.type);
    if (terminal) _finished = true;
    _lastEvent = envelope.type;

    _safely(() => onEvent?.call(PremblyEvent(
          product: envelope.product,
          type: envelope.type,
          sessionId: envelope.sessionId,
          nodeId: envelope.nodeId,
        )));
    if (terminal) {
      _safely(() => callback?.call(WorkflowResult(
          status: envelope.type, sessionId: envelope.sessionId)));
      _closeView();
    }
  }

  /// The public "dismiss early" action. Closing before the flow ended (the close button, the back
  /// gesture, or `handle.close()`) is reported once as `cancelled`. After an end state it only
  /// cleans up.
  @override
  void close() {
    if (_closed) return;
    if (!_finished) {
      _finished = true;
      _safely(() => onEvent?.call(PremblyEvent(
          product: product, type: 'cancelled', sessionId: sessionId)));
      _safely(() => callback?.call(WorkflowResult(
            status: 'cancelled',
            sessionId: sessionId,
            lastEvent: _lastEvent,
          )));
    }
    _closeView();
  }

  void _closeView() {
    if (_closed) return;
    _closed = true;
    _onClose();
  }

  void _safely(void Function() action) {
    try {
      action();
    } catch (_) {
      // A merchant callback that throws must not break the flow.
    }
  }
}
