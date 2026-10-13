import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../contract/constants.dart';
import '../contract/tm_types.dart';
import '../core/config.dart';
import '../version.dart';

/// Treat a session as expired a little early, so it is still valid when the backend screens.
const Duration _refreshMargin = Duration(seconds: 30);

class _Cached {
  _Cached(this.customerId, this.includeLocation, this.session, this.expiresAt);

  final String? customerId;
  final bool includeLocation;
  final DeviceSession session;
  final DateTime expiresAt;
}

/// `Prembly.tm`: faithful port of the TypeScript TmClient (and of PremblyTM in prembly-tm-native):
/// same behaviour, error codes and wire format. Nothing here throws, so a payment is never blocked.
class TmClient {
  TmClient({
    required TmPlatform platform,
    required http.Client client,
    DateTime Function()? now,
  })  : _platform = platform,
        _client = client,
        _now = now ?? DateTime.now;

  final TmPlatform _platform;
  final http.Client _client;
  final DateTime Function() _now;

  ResolvedConfig? _config;
  String? _customerId;
  _Cached? _cached;
  Future<DeviceSession>? _inFlight;

  /// Called by `Prembly.init`. Drops anything cached for the previous setup.
  void configure(ResolvedConfig config) {
    _config = config;
    _cached = null;
    _inFlight = null;
  }

  /// Tell Prembly who the signed-in customer is (`null` when they sign out).
  void identify(String? customerId) {
    final trimmed = customerId?.trim();
    final next = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    if (next != _customerId) {
      _customerId = next;
      _cached = null;
    }
  }

  /// Include location in device sessions. Only used when the app already holds the permission.
  void setLocationEnabled(bool enabled) {
    final config = _config;
    if (config != null && config.location != enabled) {
      _config = config.copyWith(location: enabled);
      _cached = null;
    }
  }

  void reset() {
    _customerId = null;
    _cached = null;
    _inFlight = null;
  }

  Future<String?> getDeviceId() async {
    try {
      return await _platform.getDeviceId();
    } catch (error) {
      _log('getDeviceId failed', error);
      return null;
    }
  }

  Future<SignalBundle?> getSignalsPreview() async {
    try {
      return await _platform.collectSignals(_config?.location ?? false);
    } catch (error) {
      _log('getSignalsPreview failed', error);
      return null;
    }
  }

  /// A device session for the current customer. Cached until shortly before it expires; callers
  /// that ask at the same moment share one request.
  Future<DeviceSession> getDeviceSession({bool forceRefresh = false}) {
    final config = _config;
    if (config == null) {
      return Future.value(_failed(SessionError.notInitialised, null));
    }
    if (!forceRefresh && _isCacheValid(config)) {
      return Future.value(_cached!.session);
    }

    final running = _inFlight;
    if (running != null) return running;
    final request = _createSession(config).whenComplete(() => _inFlight = null);
    _inFlight = request;
    return request;
  }

  bool _isCacheValid(ResolvedConfig config) {
    final cached = _cached;
    return cached != null &&
        cached.customerId == _customerId &&
        cached.includeLocation == config.location &&
        cached.expiresAt.subtract(_refreshMargin).isAfter(_now());
  }

  Future<DeviceSession> _createSession(ResolvedConfig config) async {
    String? deviceId;
    final Map<String, Object?> body;
    final String appId;
    try {
      deviceId = await _platform.getDeviceId();
      final signals = await _platform.collectSignals(config.location);
      appId = await _platform.getAppId();
      body = {
        ...signals,
        'device_id': deviceId,
        if (_customerId != null) 'customer_id': _customerId,
        'consent': {'location': config.location},
        'collected_at': _now().toUtc().toIso8601String(),
      };
    } catch (error) {
      _log('collecting signals failed', error);
      return _failed(SessionError.nativeError, deviceId);
    }

    try {
      final response = await _client
          .post(
            Uri.parse('${config.baseUrl}$tmSessionsPath'),
            headers: {
              'Content-Type': 'application/json',
              headerPublishableKey: config.publishableKey,
              headerAppId: appId,
              headerSdkPlatform: _platform.platform,
              headerSdkVersion: sdkVersion,
            },
            body: jsonEncode(body),
          )
          .timeout(config.timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _failed(_errorForStatus(response.statusCode), deviceId);
      }
      final payload = jsonDecode(utf8.decode(response.bodyBytes));
      final data = payload is Map ? payload['data'] : null;
      final sessionId = data is Map ? data['device_session_id'] : null;
      if (sessionId is! String || sessionId.isEmpty) {
        return _failed(SessionError.serverError, deviceId);
      }

      final expiresAt = data['expires_at'];
      final session = DeviceSession(
        deviceSessionId: sessionId,
        deviceId: data['device_id'] is String
            ? data['device_id'] as String
            : deviceId,
        isKnownDevice: data['is_known_device'] == true,
        expiresAt: expiresAt is String ? expiresAt : null,
      );
      final expiry = expiresAt is String ? DateTime.tryParse(expiresAt) : null;
      if (expiry != null) {
        _cached = _Cached(_customerId, config.location, session, expiry);
      }
      return session;
    } on TimeoutException {
      return _failed(SessionError.timeout, deviceId);
    } on SocketException {
      return _failed(SessionError.networkError, deviceId);
    } on http.ClientException {
      return _failed(SessionError.networkError, deviceId);
    } catch (error) {
      _log('session request failed', error);
      return _failed(SessionError.networkError, deviceId);
    }
  }

  SessionError _errorForStatus(int status) {
    if (status == 401 || status == 403) return SessionError.unauthorised;
    if (status == 429) return SessionError.rateLimited;
    if (status >= 400 && status < 500) return SessionError.rejected;
    return SessionError.serverError;
  }

  DeviceSession _failed(SessionError error, String? deviceId) {
    _log('no device session: ${error.wire}');
    return DeviceSession(
        deviceSessionId: null, deviceId: deviceId, error: error);
  }

  void _log(String message, [Object? detail]) {
    if (_config?.debug ?? false) {
      debugPrint('[PremblyTM] $message${detail == null ? '' : ' $detail'}');
    }
  }
}
