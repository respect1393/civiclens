import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

/// Broad category of transport/protocol failure, independent of any endpoint.
enum ApiFailure {
  /// The device could not reach the server at all.
  network,

  /// The request exceeded the client timeout.
  timeout,

  /// HTTP 400 — the payload failed server-side validation.
  badRequest,

  /// HTTP 401 — missing, invalid or expired credentials.
  unauthorized,

  /// HTTP 403 — authenticated but not allowed.
  forbidden,

  /// HTTP 404 — no such resource.
  notFound,

  /// HTTP 5xx — the server failed to handle the request.
  server,

  /// The server answered with a body the app cannot interpret.
  invalidResponse,

  /// Any other unexpected status.
  unknown,
}

/// A failed API call.
///
/// [message] is always safe to show to a citizen: it is written by this app,
/// never copied wholesale from a server payload, and never contains response
/// bodies, tokens, authorization headers or stack traces.
class ApiException implements Exception {
  ApiException({
    required this.failure,
    required this.message,
    this.statusCode,
    this.serverMessage,
    this.fieldErrors = const <String, String>{},
  });

  final ApiFailure failure;
  final String message;
  final int? statusCode;

  /// Short, developer-authored `error` string from the backend response, if
  /// any. Sanitised and length-capped, so it is still safe to display.
  final String? serverMessage;

  /// Field-level validation messages keyed by request field, extracted from
  /// the backend's Zod `details` object.
  final Map<String, String> fieldErrors;

  @override
  String toString() => message;
}

/// Generic, citizen-safe copy for each failure category.
String _genericMessage(ApiFailure failure) => switch (failure) {
  ApiFailure.network =>
    'Could not reach the server. Check your connection and try again.',
  ApiFailure.timeout => 'The request took too long. Please try again.',
  ApiFailure.badRequest =>
    'Please check the details you entered and try again.',
  ApiFailure.unauthorized => 'Your session has expired. Please sign in again.',
  ApiFailure.forbidden => 'You do not have permission to do that.',
  ApiFailure.notFound => 'That request could not be found.',
  ApiFailure.server =>
    'Something went wrong on our side. Please try again shortly.',
  ApiFailure.invalidResponse =>
    'The server sent an unexpected response. Please try again.',
  ApiFailure.unknown => 'Something went wrong. Please try again.',
};

/// Thin JSON HTTP client for the CIVICLENS backend.
///
/// Responsibilities:
/// * build requests against [ApiConfig] (never a hardcoded host),
/// * attach `Authorization: Bearer <token>` when a token is supplied,
/// * translate status codes and transport failures into [ApiException],
/// * fire [onUnauthorized] when a *token-bearing* request comes back 401, so an
///   expired session is dropped instead of retried forever.
///
/// Nothing here logs request bodies, tokens or authorization headers, and TLS
/// verification is never relaxed.
class ApiClient {
  ApiClient({
    http.Client? client,
    String? baseUrl,
    this.timeout = const Duration(seconds: 15),
    this.onUnauthorized,
  }) : _client = client ?? http.Client(),
       baseUrl = _normalise(baseUrl ?? ApiConfig.baseUrl);

  final http.Client _client;

  /// Base URL without a trailing slash.
  final String baseUrl;

  final Duration timeout;

  /// Invoked when the backend rejects a token that this app sent.
  ///
  /// Only fires for authenticated requests: a rejected *login* is a bad
  /// password, not a dead session, and must not clear anything.
  void Function()? onUnauthorized;

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) => _send('POST', path, body: body, token: token);

  Future<Map<String, dynamic>> getJson(String path, {String? token}) =>
      _send('GET', path, token: token);

  /// Uploads raw [bytes] as the body of an authenticated `POST` to [path].
  ///
  /// Used for binary uploads (report photos) where JSON encoding would inflate
  /// the payload. The response is still interpreted as JSON.
  Future<Map<String, dynamic>> postBytes(
    String path,
    List<int> bytes, {
    required String contentType,
    String? token,
  }) async {
    final uri = Uri.parse('$baseUrl${_normalisePath(path)}');
    final hasToken = token != null && token.isNotEmpty;

    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': contentType,
      if (hasToken) 'Authorization': 'Bearer $token',
    };

    final http.Response response;
    try {
      response = await _client
          .post(uri, headers: headers, body: bytes)
          .timeout(timeout);
    } on TimeoutException {
      throw ApiException(
        failure: ApiFailure.timeout,
        message: _genericMessage(ApiFailure.timeout),
      );
    } catch (_) {
      throw ApiException(
        failure: ApiFailure.network,
        message: _genericMessage(ApiFailure.network),
      );
    }

    return _interpret(response, sentToken: hasToken);
  }

  /// Fetches raw bytes from an authenticated `GET` for [path].
  ///
  /// Intended for binary resources whose access must stay authenticated (report
  /// photos). Any non-2xx status is raised as an [ApiException] so callers can
  /// distinguish "no image" from "not allowed".
  Future<Uint8List> getBytes(String path, {String? token}) async {
    final uri = Uri.parse('$baseUrl${_normalisePath(path)}');
    final hasToken = token != null && token.isNotEmpty;

    final headers = <String, String>{
      'Accept': 'application/octet-stream',
      if (hasToken) 'Authorization': 'Bearer $token',
    };

    final http.Response response;
    try {
      response = await _client.get(uri, headers: headers).timeout(timeout);
    } on TimeoutException {
      throw ApiException(
        failure: ApiFailure.timeout,
        message: _genericMessage(ApiFailure.timeout),
      );
    } catch (_) {
      throw ApiException(
        failure: ApiFailure.network,
        message: _genericMessage(ApiFailure.network),
      );
    }

    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      return response.bodyBytes;
    }

    // `_errorFor` fires `onUnauthorized` for a rejected token-bearing request.
    throw _errorFor(
      status,
      decoded: _tryDecode(response.body),
      sentToken: hasToken,
    );
  }

  /// Sends an authenticated `DELETE` for [path].
  ///
  /// A `204` (or any other 2xx) with an empty body is treated as success and
  /// resolved to an empty map, so callers only need to know that the request
  /// completed. Errors are interpreted exactly as for GET/POST.
  Future<Map<String, dynamic>> deleteJson(String path, {String? token}) =>
      _send('DELETE', path, token: token);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final uri = Uri.parse('$baseUrl${_normalisePath(path)}');
    final hasToken = token != null && token.isNotEmpty;

    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (hasToken) 'Authorization': 'Bearer $token',
    };

    final http.Response response;
    try {
      final Future<http.Response> pending;
      switch (method) {
        case 'POST':
          pending = _client.post(
            uri,
            headers: headers,
            body: jsonEncode(body ?? const <String, dynamic>{}),
          );
        case 'DELETE':
          pending = _client.delete(uri, headers: headers);
        default:
          pending = _client.get(uri, headers: headers);
      }
      response = await pending.timeout(timeout);
    } on TimeoutException {
      throw ApiException(
        failure: ApiFailure.timeout,
        message: _genericMessage(ApiFailure.timeout),
      );
    } catch (_) {
      // SocketException, ClientException, handshake and DNS failures.
      throw ApiException(
        failure: ApiFailure.network,
        message: _genericMessage(ApiFailure.network),
      );
    }

    return _interpret(response, sentToken: hasToken);
  }

  Map<String, dynamic> _interpret(
    http.Response response, {
    required bool sentToken,
  }) {
    final status = response.statusCode;
    final decoded = _tryDecode(response.body);

    if (status >= 200 && status < 300) {
      // A `204 No Content` (used by DELETE) has no body and is a success.
      if (decoded == null) return const <String, dynamic>{};
      if (decoded is! Map<String, dynamic>) {
        throw ApiException(
          failure: ApiFailure.invalidResponse,
          message: _genericMessage(ApiFailure.invalidResponse),
          statusCode: status,
        );
      }
      return decoded;
    }

    throw _errorFor(status, decoded: decoded, sentToken: sentToken);
  }

  /// Builds the citizen-safe [ApiException] for a non-2xx [status].
  ///
  /// Fires [onUnauthorized] for a rejected token-bearing request. Shared by the
  /// JSON and binary code paths so both classify failures identically.
  ApiException _errorFor(
    int status, {
    required bool sentToken,
    Object? decoded,
  }) {
    if (status == 401 && sentToken) {
      onUnauthorized?.call();
    }

    final failure = switch (status) {
      400 => ApiFailure.badRequest,
      401 => ApiFailure.unauthorized,
      403 => ApiFailure.forbidden,
      404 => ApiFailure.notFound,
      >= 500 => ApiFailure.server,
      _ => ApiFailure.unknown,
    };

    return ApiException(
      failure: failure,
      message: _genericMessage(failure),
      statusCode: status,
      serverMessage: _serverMessage(decoded),
      fieldErrors: _fieldErrors(decoded),
    );
  }

  static Object? _tryDecode(String body) {
    if (body.trim().isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  static String? _serverMessage(Object? decoded) {
    if (decoded is! Map) return null;
    final error = decoded['error'];
    return error is String ? _sanitise(error) : null;
  }

  /// Flattens the backend's Zod `format()` output into `field -> message`.
  ///
  /// Shape: `{ "_errors": [...], "email": { "_errors": ["Invalid email"] } }`.
  static Map<String, String> _fieldErrors(Object? decoded) {
    final errors = <String, String>{};

    void walk(Object? node, String path) {
      if (node is! Map) return;

      final own = node['_errors'];
      if (own is List && path.isNotEmpty && errors[path] == null) {
        for (final item in own) {
          final message = item is String ? _sanitise(item) : '';
          if (message.isNotEmpty) {
            errors[path] = message;
            break;
          }
        }
      }

      node.forEach((key, value) {
        if (key == '_errors') return;
        final child = path.isEmpty ? '$key' : '$path.$key';
        walk(value, child);
      });
    }

    if (decoded is Map) {
      walk(decoded['details'], '');
    }
    return errors;
  }

  /// Makes untrusted server text safe to render: single line, bounded length.
  static String _sanitise(String value) {
    final collapsed = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.isEmpty) return '';
    return collapsed.length <= 180
        ? collapsed
        : '${collapsed.substring(0, 177)}...';
  }

  static String _normalise(String value) {
    final trimmed = value.trim();
    final withoutSlash = trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    return withoutSlash.isEmpty ? ApiConfig.desktopBaseUrl : withoutSlash;
  }

  static String _normalisePath(String path) =>
      path.startsWith('/') ? path : '/$path';
}
