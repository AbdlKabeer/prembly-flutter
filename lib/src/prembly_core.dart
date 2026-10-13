import 'package:http/http.dart' as http;

import 'contract/constants.dart';
import 'contract/errors.dart';
import 'contract/keys.dart';
import 'contract/tm_types.dart';
import 'contract/workflow_types.dart';
import 'core/config.dart';
import 'tm/method_channel_tm_platform.dart';
import 'tm/tm_client.dart';
import 'version.dart';
import 'workflow/workflow_api.dart';
import 'workflow/workflow_screen.dart';

/// The wiring behind `Prembly`. Built with its dependencies so tests can swap them.
class PremblyCore {
  PremblyCore({http.Client? client, TmPlatform? platform, Launcher? launcher}) {
    final httpClient = client ?? http.Client();
    final tmPlatform = platform ?? MethodChannelTmPlatform();
    tm = TmClient(platform: tmPlatform, client: httpClient);
    workflow = WorkflowApi(
      getConfig: _requireConfig,
      launcher: launcher ?? launchWorkflowScreen,
      client: httpClient,
      platform: tmPlatform.platform,
      appId: tmPlatform.getAppId,
    );
  }

  late final TmClient tm;
  late final WorkflowApi workflow;
  ResolvedConfig? _config;

  ResolvedConfig _requireConfig() {
    final config = _config;
    if (config == null) {
      throw PremblyError(
        ErrorCode.notInitialised,
        'Prembly.init(publishableKey: ...) must be called first.',
      );
    }
    return config;
  }

  /// Sets up the SDK once. The key prefix decides the environment. Throws on a bad key.
  void init({
    required String publishableKey,
    String? baseUrl,
    bool location = false,
    Duration? timeout,
    bool debug = false,
    String? hostedUrl,
  }) {
    final key = parsePublishableKey(publishableKey);
    final config = ResolvedConfig(
      publishableKey: key.publishableKey,
      environment: key.environment,
      baseUrl: (baseUrl ?? defaultBaseUrl).replaceAll(RegExp(r'/+$'), ''),
      location: location,
      timeout: timeout ?? defaultTimeout,
      debug: debug,
      hostedUrl: hostedUrl ?? defaultHostedUrl,
    );
    _config = config;
    tm.configure(config);
  }

  String get version => sdkVersion;

  Environment? get environment => _config?.environment;
}
