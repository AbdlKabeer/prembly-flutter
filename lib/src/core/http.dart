import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../contract/errors.dart';

/// POSTs JSON and returns the parsed body, or throws a [PremblyError] with a mapped code.
/// Used by products that surface errors (TM has its own fail-open mapping).
Future<Map<String, Object?>?> postJson({
  required http.Client client,
  required Uri url,
  required Map<String, String> headers,
  required Object body,
  required Duration timeout,
}) async {
  try {
    final response = await client
        .post(url, headers: headers, body: jsonEncode(body))
        .timeout(timeout);

    Map<String, Object?>? payload;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map) payload = Map<String, Object?>.from(decoded);
    } catch (_) {
      payload = null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = payload?['message'];
      throw PremblyError(
        errorCodeForStatus(response.statusCode),
        message is String && message.isNotEmpty
            ? message
            : 'Request failed with status ${response.statusCode}',
        status: response.statusCode,
        details: payload?['errors'],
      );
    }
    return payload;
  } on PremblyError {
    rethrow;
  } on TimeoutException {
    throw PremblyError(ErrorCode.timeout, 'The request timed out.');
  } on SocketException {
    throw PremblyError(ErrorCode.networkError,
        'Could not reach Prembly. Check the connection.');
  } on http.ClientException {
    throw PremblyError(ErrorCode.networkError,
        'Could not reach Prembly. Check the connection.');
  } catch (error) {
    throw PremblyError(ErrorCode.networkError, error.toString());
  }
}
