import 'dart:convert';
import 'dart:typed_data';

import '../config/api_config.dart';
import 'api_exception.dart';
import 'api_response.dart';
import 'create_transport.dart';
import 'http_transport.dart';

typedef AccessTokenProvider = String? Function();

/// Owns its transport. An optional session owner can recover a rejected bearer
/// once; connectivity failures and other mutation errors are never retried.
class ApiClient {
  ApiClient({
    required this.config,
    HttpTransport? transport,
    this.accessTokenProvider,
    this.beforeAuthenticatedRequest,
    this.recoverAuthentication,
    this.onSessionRejected,
  }) : _transport = transport ?? createTransport();
  final ApiConfig config;
  final HttpTransport _transport;
  final AccessTokenProvider? accessTokenProvider;
  bool _closed = false;
  final Future<void> Function()? beforeAuthenticatedRequest;
  final Future<bool> Function(String rejectedToken)? recoverAuthentication;
  final Future<void> Function(String rejectedToken)? onSessionRejected;

  Future<ApiResponse<T>> request<T>(
    String method,
    String path, {
    required JsonDecoder<T> decode,
    Map<String, String>? query,
    Object? body,
    BinaryRequestBody? encodedBody,
    bool authenticated = false,
    bool manageSession = true,
    bool recoverUnauthorized = true,
    bool pdfResponse = false,
    // Recheck the resource owner after async token work and before decoding.
    void Function()? accessGuard,
  }) async {
    if (_closed) throw StateError('API client is closed');
    if (body != null && encodedBody != null) {
      throw ArgumentError('Supply either JSON or an encoded body.');
    }
    accessGuard?.call();
    if (authenticated && manageSession) {
      await beforeAuthenticatedRequest?.call();
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      accessGuard?.call();
      final token = authenticated ? accessTokenProvider?.call() : null;
      try {
        return await _request(
          method,
          path,
          decode: decode,
          query: query,
          body: body,
          encodedBody: encodedBody,
          authenticated: authenticated,
          accessToken: token,
          pdfResponse: pdfResponse,
          accessGuard: accessGuard,
        );
      } on ApiException catch (error) {
        accessGuard?.call();
        if (!authenticated ||
            !manageSession ||
            !recoverUnauthorized ||
            error.kind != ApiErrorKind.unauthorized) {
          rethrow;
        }
        if (attempt == 0 && token != null && recoverAuthentication != null) {
          final recovered = await recoverAuthentication!(token);
          accessGuard?.call();
          if (recovered) continue;
        }
        if (token != null) await onSessionRejected?.call(token);
        rethrow;
      }
    }
    throw StateError('Unreachable request state');
  }

  Future<ApiResponse<T>> _request<T>(
    String method,
    String path, {
    required JsonDecoder<T> decode,
    Map<String, String>? query,
    Object? body,
    BinaryRequestBody? encodedBody,
    bool authenticated = false,
    String? accessToken,
    bool pdfResponse = false,
    void Function()? accessGuard,
  }) async {
    if (_closed) throw StateError('API client is closed');
    if (body != null && encodedBody != null) {
      throw ArgumentError('Supply either JSON or an encoded body.');
    }
    final uri = config.endpoint(path, query);
    final headers = <String, String>{
      'Accept': pdfResponse ? 'application/pdf' : 'application/json',
    };
    if (encodedBody != null) {
      headers['Content-Type'] = encodedBody.contentType;
    } else if (body != null) {
      headers['Content-Type'] = 'application/json; charset=utf-8';
    }
    if (authenticated) {
      final token = accessToken;
      if (token == null || token.isEmpty) {
        throw const ApiException(
          kind: ApiErrorKind.unauthorized,
          message: 'Please sign in to continue.',
        );
      }
      headers['Authorization'] = 'Bearer $token';
    }
    accessGuard?.call();
    final response = await _transport.send(
      TransportRequest(
        method: method.toUpperCase(),
        uri: uri,
        headers: headers,
        timeout: config.timeout,
        body: body == null ? null : jsonEncode(body),
        bodyBytes: encodedBody?.bytes,
        receiveBytes: pdfResponse,
      ),
    );
    accessGuard?.call();
    final httpSuccess = response.statusCode >= 200 && response.statusCode < 300;
    if (httpSuccess && pdfResponse) {
      try {
        return ApiResponse(message: '', data: decode(response.bodyBytes));
      } on FormatException {
        throw _invalidResponse(response.statusCode);
      } on TypeError {
        throw _invalidResponse(response.statusCode);
      }
    }
    Map<String, dynamic>? envelope;
    try {
      final parsed = jsonDecode(response.body);
      if (parsed is Map<String, dynamic>) envelope = parsed;
    } on FormatException {
      // Non-JSON failures (for example a proxy HTML page) use safe fallbacks.
    }
    if (!httpSuccess || envelope?['success'] == false) {
      final message = envelope?['message'];
      final errors = envelope?['data'];
      throw ApiException(
        kind: ApiException.kindForStatus(response.statusCode),
        statusCode: response.statusCode,
        message: message is String && message.trim().isNotEmpty
            ? message
            : ApiException.messageForStatus(response.statusCode),
        fieldErrors: Map.unmodifiable(
          errors is Map
              ? <String, String>{
                  for (final entry in errors.entries)
                    if (entry.key is String && entry.value is String)
                      entry.key as String: entry.value as String,
                }
              : <String, String>{},
        ),
      );
    }
    if (envelope == null ||
        envelope['success'] != true ||
        envelope['message'] is! String ||
        !envelope.containsKey('data') ||
        (envelope['timestamp'] != null && envelope['timestamp'] is! String)) {
      throw _invalidResponse(response.statusCode);
    }
    try {
      return ApiResponse(
        message: envelope['message'] as String,
        data: decode(envelope['data']),
        timestamp: envelope['timestamp'] as String?,
      );
    } on FormatException {
      throw _invalidResponse(response.statusCode);
    } on TypeError {
      throw _invalidResponse(response.statusCode);
    }
  }

  ApiException _invalidResponse(int status) => ApiException(
    kind: ApiErrorKind.invalidResponse,
    statusCode: status,
    message: 'The service returned unreadable information.',
  );

  void close() {
    if (_closed) return;
    _closed = true;
    _transport.close();
  }

  /// Raw authenticated PDF endpoint; retains the normal refresh/rejection flow.
  Future<Uint8List> downloadPdf(
    String path, {
    void Function()? accessGuard,
  }) async => (await request(
    'GET',
    path,
    authenticated: true,
    pdfResponse: true,
    accessGuard: accessGuard,
    decode: (value) {
      if (value is! Uint8List ||
          value.length < 5 ||
          ascii.decode(value.sublist(0, 5), allowInvalid: true) != '%PDF-') {
        throw const FormatException('Invalid PDF response');
      }
      return value;
    },
  )).data;
}
