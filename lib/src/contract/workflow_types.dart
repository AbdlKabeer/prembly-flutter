import 'package:flutter/widgets.dart';

/// Public event handed to `onEvent`. Built from the wire envelope.
class PremblyEvent {
  const PremblyEvent({
    required this.product,
    required this.type,
    required this.sessionId,
    this.nodeId,
  });

  final String product;
  final String type;
  final String sessionId;
  final String? nodeId;

  @override
  String toString() =>
      'PremblyEvent($product, $type, $sessionId${nodeId == null ? '' : ', $nodeId'})';
}

class WorkflowCustomer {
  const WorkflowCustomer({
    required this.firstName,
    required this.lastName,
    required this.email,
    this.phone,
    this.reference,
  });

  final String firstName;
  final String lastName;
  final String email;
  final String? phone;
  final String? reference;
}

/// Why a flow could not start (`failed`) or is not offered here (`not_available`).
class WorkflowError {
  const WorkflowError(this.code, this.message);

  final String code;
  final String message;
}

/// What `callback` receives, once, when the flow ends.
///
/// `status` is one of `completed`, `failed`, `manual_review`, `expired` (sent by the hosted app),
/// `cancelled` (closed before the end), or `failed` / `not_available` with an [error] when the
/// flow could not start. It never carries personal data.
class WorkflowResult {
  const WorkflowResult(
      {required this.status, this.sessionId, this.lastEvent, this.error});

  final String status;
  final String? sessionId;

  /// For `cancelled`: the last event seen before the close. `processing` means the person had
  /// finished their steps and the checks were still running, so the session carries on in the
  /// background.
  final String? lastEvent;
  final WorkflowError? error;

  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';

  @override
  String toString() =>
      'WorkflowResult($status${sessionId == null ? '' : ', $sessionId'}${lastEvent == null ? '' : ', lastEvent: $lastEvent'}${error == null ? '' : ', error: ${error!.code}'})';
}

typedef WorkflowCallback = void Function(WorkflowResult result);
typedef PremblyEventHandler = void Function(PremblyEvent event);

abstract class WorkflowHandle {
  /// Closes the flow. Before an end state this is reported once as `cancelled`.
  void close();
}

/// What a launcher is given to show a hosted product.
class LaunchOptions {
  const LaunchOptions({
    required this.context,
    required this.product,
    required this.sessionId,
    required this.link,
    this.onEvent,
    this.callback,
  });

  final BuildContext context;
  final String product;
  final String sessionId;
  final String link;
  final PremblyEventHandler? onEvent;
  final WorkflowCallback? callback;
}

typedef Launcher = WorkflowHandle Function(LaunchOptions options);
