/// Why no device session could be created. Nothing throws: a payment is never blocked.
enum SessionError {
  notInitialised('not_initialised'),
  timeout('timeout'),
  networkError('network_error'),
  unauthorised('unauthorised'),
  rateLimited('rate_limited'),
  rejected('rejected'),
  serverError('server_error'),
  nativeError('native_error');

  const SessionError(this.wire);
  final String wire;
}

class DeviceSession {
  const DeviceSession({
    required this.deviceSessionId,
    required this.deviceId,
    this.isKnownDevice,
    this.expiresAt,
    this.error,
  });

  /// Send to your backend with the transaction. `null` when no session could be created.
  final String? deviceSessionId;
  final String? deviceId;
  final bool? isKnownDevice;
  final String? expiresAt;
  final SessionError? error;

  bool get isValid => deviceSessionId != null;

  @override
  String toString() =>
      'DeviceSession(${deviceSessionId ?? 'none'}${error == null ? '' : ', error: ${error!.wire}'})';
}

/// Signals grouped the way the API expects. Signals a platform cannot provide are omitted.
typedef SignalBundle = Map<String, Object?>;

/// What a platform provides to the shared TM client.
abstract class TmPlatform {
  /// Sent as X-SDK-Platform: `ios` or `android`.
  String get platform;
  Future<String?> getDeviceId();
  Future<SignalBundle> collectSignals(bool includeLocation);
  Future<String> getAppId();
}
