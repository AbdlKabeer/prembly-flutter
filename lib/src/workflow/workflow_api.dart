import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../contract/constants.dart';
import '../contract/errors.dart';
import '../contract/workflow_types.dart';
import '../core/config.dart';
import '../core/http.dart';
import '../version.dart';

final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

bool _nonEmpty(String? value) => value != null && value.trim().isNotEmpty;

PremblyError _bad(String message) =>
    PremblyError(ErrorCode.invalidRequest, 'workflow.start: $message');

void _validate(
    {required String workflowId, required WorkflowCustomer customer}) {
  if (!_nonEmpty(workflowId)) throw _bad('workflowId is required.');
  if (!_nonEmpty(customer.firstName) || !_nonEmpty(customer.lastName)) {
    throw _bad('customer.firstName and customer.lastName are required.');
  }
  if (!_nonEmpty(customer.email) || !_emailPattern.hasMatch(customer.email)) {
    throw _bad('customer.email must be a valid email.');
  }
}

Map<String, Object?> _toRequest({
  required String workflowId,
  required WorkflowCustomer customer,
  required Map<String, Object?> metadata,
  required String? redirectUrl,
}) =>
    {
      'workflow_id': workflowId,
      'customer': {
        'first_name': customer.firstName,
        'last_name': customer.lastName,
        'email': customer.email,
        if (customer.phone != null) 'phone': customer.phone,
        if (customer.reference != null) 'reference': customer.reference,
      },
      'metadata': metadata,
      if (redirectUrl != null) 'redirect_url': redirectUrl,
    };

/// `<hostedUrl>?session=<id>`, keeping any query the hosted URL already has.
String buildHostedLink(String hostedUrl, String sessionId) {
  final Uri url;
  try {
    url = Uri.parse(hostedUrl);
    if (!url.hasScheme || url.host.isEmpty) throw const FormatException();
  } catch (_) {
    throw PremblyError(
        ErrorCode.invalidRequest, 'Prembly: hostedUrl is not a valid URL.');
  }
  return url.replace(queryParameters: {
    ...url.queryParameters,
    'session': sessionId
  }).toString();
}

/// `Prembly.workflow`: start a workflow for a customer, or open one your backend created.
class WorkflowApi {
  WorkflowApi({
    required ResolvedConfig Function() getConfig,
    required Launcher launcher,
    required http.Client client,
    required String platform,
    required Future<String> Function() appId,
  })  : _getConfig = getConfig,
        _launcher = launcher,
        _client = client,
        _platform = platform,
        _appId = appId;

  final ResolvedConfig Function() _getConfig;
  final Launcher _launcher;
  final http.Client _client;
  final String _platform;
  final Future<String> Function() _appId;

  /// Opens a session your backend already created. Never throws `not_available`.
  WorkflowHandle open({
    required BuildContext context,
    required String sessionId,
    String? link,
    String? hostedUrl,
    PremblyEventHandler? onEvent,
    WorkflowCallback? callback,
  }) {
    if (!_nonEmpty(sessionId)) {
      throw PremblyError(
          ErrorCode.invalidRequest, 'workflow.open: sessionId is required.');
    }
    final target =
        link ?? buildHostedLink(hostedUrl ?? _getConfig().hostedUrl, sessionId);
    return _launcher(LaunchOptions(
      context: context,
      product: 'workflow',
      sessionId: sessionId,
      link: target,
      onEvent: onEvent,
      callback: callback,
    ));
  }

  /// Creates a session for the customer and opens it. Throws a [PremblyError] and also calls
  /// `callback(failed)` (or `not_available`) when it cannot start.
  Future<WorkflowHandle> start({
    required BuildContext context,
    required String workflowId,
    required WorkflowCustomer customer,
    Map<String, Object?> metadata = const {},
    String? redirectUrl,
    PremblyEventHandler? onEvent,
    WorkflowCallback? callback,
  }) async {
    try {
      _validate(workflowId: workflowId, customer: customer);
      final config = _getConfig();
      final appId = await _appId();
      final timeout = config.timeout > defaultWorkflowTimeout
          ? config.timeout
          : defaultWorkflowTimeout;

      final response = await postJson(
        client: _client,
        url: Uri.parse('${config.baseUrl}$workflowSessionsPath'),
        timeout: timeout,
        headers: {
          'Content-Type': 'application/json',
          headerPublishableKey: config.publishableKey,
          headerSdkPlatform: _platform,
          headerSdkVersion: sdkVersion,
          headerAppId: appId,
        },
        body: _toRequest(
          workflowId: workflowId,
          customer: customer,
          metadata: metadata,
          redirectUrl: redirectUrl,
        ),
      );

      final data = response?['data'];
      final sessionId = data is Map ? data['session_id'] : null;
      final link = data is Map ? data['link'] : null;
      if (sessionId is! String ||
          sessionId.trim().isEmpty ||
          link is! String ||
          link.trim().isEmpty) {
        throw PremblyError(ErrorCode.serverError,
            'The workflow session response was incomplete.');
      }
      // The caller's context may have gone while the request ran.
      if (!context.mounted) {
        throw PremblyError(ErrorCode.invalidRequest,
            'workflow.start: the context is no longer mounted.');
      }
      return open(
        context: context,
        sessionId: sessionId,
        link: link,
        onEvent: onEvent,
        callback: callback,
      );
    } catch (error) {
      final err = error is PremblyError
          ? error
          : PremblyError(ErrorCode.networkError, error.toString());
      _report(callback, err);
      throw err;
    }
  }

  void _report(WorkflowCallback? callback, PremblyError error) {
    if (callback == null) return;
    try {
      callback(WorkflowResult(
        status:
            error.code == ErrorCode.notAvailable ? 'not_available' : 'failed',
        error: WorkflowError(error.code.wire, error.message),
      ));
    } catch (_) {
      // A merchant callback that throws must not break the SDK.
    }
  }
}
