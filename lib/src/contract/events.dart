import 'constants.dart';

const List<String> workflowEventTypes = [
  'loaded',
  'step_started',
  'step_completed',
  'processing',
  'completed',
  'failed',
  'manual_review',
  'expired',
  // The person used the widget's own Cancel button. It is not an end state: the flow handles it
  // like the app's close button, so it is reported as `cancelled` with the last event seen.
  'cancelled',
];

const List<String> terminalEventTypes = [
  'completed',
  'failed',
  'manual_review',
  'expired'
];

bool isTerminalType(String type) => terminalEventTypes.contains(type);

/// The wire envelope posted by a hosted app. Never carries personal data.
class EventEnvelope {
  const EventEnvelope({
    required this.product,
    required this.sessionId,
    required this.type,
    this.nodeId,
  });

  final String product;
  final String sessionId;
  final String type;
  final String? nodeId;
}

/// Turns a received message into an envelope, or `null` if it is not one of ours.
///
/// Accepts the new envelope and the legacy `prembly-workflow-sdk` shape (product defaults to
/// "workflow"). Origin and source-window checks are the receiver's job, not done here.
EventEnvelope? normaliseEnvelope(Object? data) {
  if (data is! Map) return null;
  final type = data['type'];
  final sessionId = data['session_id'];
  if (type is! String || sessionId is! String) return null;

  final String product;
  if (data['source'] == eventSource) {
    final p = data['product'];
    if (p is! String || p.isEmpty) return null;
    product = p;
  } else if (data['source'] == legacyWorkflowEventSource) {
    product = 'workflow';
  } else {
    return null;
  }
  if (product == 'workflow' && !workflowEventTypes.contains(type)) return null;

  final nodeId = data['node_id'];
  return EventEnvelope(
    product: product,
    sessionId: sessionId,
    type: type,
    nodeId: nodeId is String ? nodeId : null,
  );
}
