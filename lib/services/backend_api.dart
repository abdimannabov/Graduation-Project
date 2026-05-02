import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/local_dev_network_config.dart';

class MarkResult {
  const MarkResult({
    required this.ok,
    this.code,
    this.message,
    this.statusCode,
  });

  final bool ok;
  final String? code;
  final String? message;
  final int? statusCode;
}

class BackendApi {
  BackendApi({
    http.Client? client,
    String? baseUrl,
    Duration timeout = const Duration(seconds: 12),
  }) : _client = client ?? http.Client(),
       _baseUrl = _resolveBaseUrl(baseUrl),
       _timeout = timeout;

  final http.Client _client;
  final String _baseUrl;
  final Duration _timeout;

  String get baseUrl => _baseUrl;

  static String _resolveBaseUrl(String? explicitBaseUrl) {
    final configured = (explicitBaseUrl ?? _configuredBaseUrlFromBuild())
        .trim();
    if (configured.isNotEmpty) {
      return _stripTrailingSlash(configured);
    }

    // Fall back to local dev config (works in both debug and release)
    return LocalDevNetworkConfig.backendBaseUrl;
  }

  static String _configuredBaseUrlFromBuild() {
    const upper = String.fromEnvironment('BACKEND_BASE_URL');
    if (upper.trim().isNotEmpty) return upper;

    // Support the lowercase dart-define name used in some build notes/scripts.
    const lower = String.fromEnvironment('backend_base_url');
    return lower;
  }

  static String _stripTrailingSlash(String value) {
    return value.replaceFirst(RegExp(r'/+$'), '');
  }

  String? get backendHost {
    try {
      final uri = Uri.parse(_baseUrl);
      return uri.host.trim().toLowerCase();
    } catch (_) {
      return null;
    }
  }

  bool qrHostMatchesBackend(String scannedValue) {
    final expectedHost = backendHost;
    if (expectedHost == null || expectedHost.isEmpty) return false;

    Uri qrUri;
    try {
      qrUri = Uri.parse(scannedValue);
    } catch (_) {
      // Signed backend QR tokens are not URLs; the backend validates them.
      return true;
    }

    if (!qrUri.hasScheme || qrUri.host.isEmpty) {
      return true;
    }

    return qrUri.host.trim().toLowerCase() == expectedHost;
  }

  Future<MarkResult> markAttendance({
    required String scannedValue,
    required String userEmail,
    Map<String, dynamic>? wifiData,
  }) async {
    if (_baseUrl.isEmpty) {
      return const MarkResult(
        ok: false,
        code: 'BACKEND_NOT_CONFIGURED',
        message:
            'Attendance server is not configured for this build. Set BACKEND_BASE_URL first.',
      );
    }

    final uri = Uri.parse('$_baseUrl/api/attendance/mark');
    final body = <String, dynamic>{'qrToken': scannedValue};
    if (wifiData != null && wifiData.isNotEmpty) {
      body['wifiData'] = wifiData;
    }

    String? idToken;
    try {
      idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {
      idToken = null;
    }

    http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/json',
              if (userEmail.isNotEmpty) 'x-user-email': userEmail,
              if (idToken != null && idToken.isNotEmpty)
                'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } on TimeoutException {
      return const MarkResult(
        ok: false,
        code: 'TIMEOUT',
        message: 'Request timed out. Please try again.',
      );
    } on SocketException {
      return const MarkResult(
        ok: false,
        code: 'NETWORK_ERROR',
        message: 'Cannot reach the attendance server.',
      );
    } on http.ClientException catch (e) {
      return MarkResult(
        ok: false,
        code: 'NETWORK_ERROR',
        message: 'HTTP client error: ${e.message}',
      );
    } catch (e) {
      return MarkResult(
        ok: false,
        code: 'REQUEST_ERROR',
        message: 'Unexpected request error: $e',
      );
    }

    Map<String, dynamic>? payload;
    if (response.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          payload = decoded;
        } else {
          return MarkResult(
            ok: false,
            code: 'INVALID_JSON',
            message: 'Server returned unexpected response format.',
            statusCode: response.statusCode,
          );
        }
      } on FormatException {
        return MarkResult(
          ok: false,
          code: 'INVALID_JSON',
          message: 'Server returned invalid JSON.',
          statusCode: response.statusCode,
        );
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final code =
          payload?['code']?.toString() ?? 'HTTP_${response.statusCode}';
      final message =
          payload?['message']?.toString() ??
          'Request failed with status ${response.statusCode}.';
      return MarkResult(
        ok: false,
        code: code,
        message: message,
        statusCode: response.statusCode,
      );
    }

    final ok = payload?['ok'] == true;
    if (ok) {
      return MarkResult(
        ok: true,
        message:
            payload?['message']?.toString() ??
            'Attendance marked successfully.',
        statusCode: response.statusCode,
      );
    }

    return MarkResult(
      ok: false,
      code: payload?['code']?.toString() ?? 'MARK_FAILED',
      message:
          payload?['message']?.toString() ??
          'Attendance was not marked. Please try again.',
      statusCode: response.statusCode,
    );
  }
}
