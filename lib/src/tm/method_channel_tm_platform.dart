import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../contract/tm_types.dart';

/// Reads the device signals through the native side (Kotlin on Android, Swift on iOS). The native
/// code is a port of prembly-tm-native, so both SDKs send the same signals.
class MethodChannelTmPlatform implements TmPlatform {
  MethodChannelTmPlatform({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('prembly/tm');

  final MethodChannel _channel;

  @override
  String get platform =>
      defaultTargetPlatform == TargetPlatform.android ? 'android' : 'ios';

  @override
  Future<String?> getDeviceId() => _channel.invokeMethod<String>('getDeviceId');

  @override
  Future<SignalBundle> collectSignals(bool includeLocation) async {
    final json = await _channel.invokeMethod<String>(
        'collectSignals', {'includeLocation': includeLocation});
    final decoded = json == null ? null : jsonDecode(json);
    if (decoded is! Map) {
      throw const FormatException('The native side returned no signals.');
    }
    return Map<String, Object?>.from(decoded);
  }

  @override
  Future<String> getAppId() async {
    final json = await _channel.invokeMethod<String>('getAppInfo');
    final decoded = json == null ? null : jsonDecode(json);
    final appId = decoded is Map ? decoded['appId'] : null;
    return appId is String && appId.isNotEmpty ? appId : 'unknown';
  }
}
