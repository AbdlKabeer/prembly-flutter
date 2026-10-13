import '../contract/keys.dart';

class ResolvedConfig {
  const ResolvedConfig({
    required this.publishableKey,
    required this.environment,
    required this.baseUrl,
    required this.location,
    required this.timeout,
    required this.debug,
    required this.hostedUrl,
  });

  final String publishableKey;
  final Environment environment;
  final String baseUrl;

  /// Include location in Transaction Monitoring. Off by default.
  final bool location;
  final Duration timeout;
  final bool debug;

  /// Hosted workflow app origin used by `workflow.open` when no `link` is given.
  final String hostedUrl;

  ResolvedConfig copyWith({bool? location}) => ResolvedConfig(
        publishableKey: publishableKey,
        environment: environment,
        baseUrl: baseUrl,
        location: location ?? this.location,
        timeout: timeout,
        debug: debug,
        hostedUrl: hostedUrl,
      );
}
