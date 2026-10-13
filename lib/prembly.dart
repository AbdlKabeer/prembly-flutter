/// Prembly for Flutter: hosted workflows and Transaction Monitoring behind one entry point.
///
/// ```dart
/// Prembly.init(publishableKey: 'test_pk_xxx');
/// await Prembly.workflow.start(context: context, workflowId: 'wf_123', customer: ...);
/// final session = await Prembly.tm.getDeviceSession();
/// ```
library;

import 'src/contract/keys.dart';
import 'src/prembly_core.dart';
import 'src/tm/tm_client.dart';
import 'src/workflow/workflow_api.dart';

export 'src/contract/errors.dart' show ErrorCode, PremblyError;
export 'src/contract/keys.dart' show Environment;
export 'src/contract/tm_types.dart'
    show DeviceSession, SessionError, SignalBundle;
export 'src/contract/workflow_types.dart'
    show
        PremblyEvent,
        PremblyEventHandler,
        WorkflowCallback,
        WorkflowCustomer,
        WorkflowError,
        WorkflowHandle,
        WorkflowResult;
export 'src/tm/tm_client.dart' show TmClient;
export 'src/workflow/workflow_api.dart' show WorkflowApi;

/// `Prembly.init`, `Prembly.workflow` and `Prembly.tm`, as in the JavaScript SDK.
class Prembly {
  Prembly._();

  static final PremblyCore _core = PremblyCore();

  /// Set up the SDK once, early. Use a `test_pk_...` key for sandbox and `live_pk_...` for live:
  /// the prefix is the only thing that decides the environment. Throws on anything else, including
  /// a secret key.
  static void init({
    required String publishableKey,
    String? baseUrl,
    bool location = false,
    Duration? timeout,
    bool debug = false,
    String? hostedUrl,
  }) =>
      _core.init(
        publishableKey: publishableKey,
        baseUrl: baseUrl,
        location: location,
        timeout: timeout,
        debug: debug,
        hostedUrl: hostedUrl,
      );

  /// Start a workflow for a customer, or open one your backend created.
  static WorkflowApi get workflow => _core.workflow;

  /// Transaction Monitoring: identify the customer and get a device session ID.
  static TmClient get tm => _core.tm;

  static String get version => _core.version;

  /// The environment chosen by the key, or `null` before [init].
  static Environment? get environment => _core.environment;
}
