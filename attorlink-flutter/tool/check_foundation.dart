// Runs with the installed Dart binary directly; requires no pub operation.
// CLI check results are intentionally printed.
// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:attorlink_flutter/core/config/api_config.dart';
import 'package:attorlink_flutter/core/network/api_client.dart';
import 'package:attorlink_flutter/core/network/api_exception.dart';
import 'package:attorlink_flutter/core/network/api_response.dart';
import 'package:attorlink_flutter/core/network/http_transport.dart';

class _Transport implements HttpTransport {
  TransportResponse response = const TransportResponse(
    statusCode: 200,
    body: '',
  );
  final List<TransportRequest> requests = [];
  bool closed = false;

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    requests.add(request);
    return response;
  }

  @override
  void close() => closed = true;
}

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<ApiException> expectApiError(
  Future<Object?> future,
  ApiErrorKind kind,
) async {
  try {
    await future;
  } on ApiException catch (error) {
    check(error.kind == kind, 'Expected $kind, got ${error.kind}');
    return error;
  }
  throw StateError('Expected an API error');
}

Future<void> main() async {
  final config = ApiConfig(baseUrl: Uri.parse('https://example.test/api/v1'));
  check(
    config.endpoint('lawyers/discover', {
          'search': 'A & B',
        }).queryParameters['search'] ==
        'A & B',
    'Query encoding failed',
  );
  for (final path in [
    'https://other.test',
    '//other.test',
    '/users',
    '../admin',
    '%2e%2e/admin',
    '..%2fadmin',
    r'..\admin',
    'users?x=1',
    'users#x',
  ]) {
    var rejected = false;
    try {
      config.endpoint(path);
    } on ArgumentError {
      rejected = true;
    }
    check(rejected, 'Unsafe endpoint accepted: $path');
  }
  print('PASS API URL configuration and path restrictions');

  final transport = _Transport();
  var token = 'first';
  final api = ApiClient(
    config: config,
    transport: transport,
    accessTokenProvider: () => token,
  );
  transport.response = TransportResponse(
    statusCode: 200,
    body: jsonEncode({
      'success': true,
      'message': 'OK',
      'data': {'id': 7},
      'timestamp': '2026-11-04T16:00:00',
    }),
  );
  final result = await api.request<int>(
    'post',
    'users/me',
    authenticated: true,
    body: {'text': 'বাংলা'},
    decode: (v) => (v as Map)['id'] as int,
  );
  check(
    result.data == 7 && result.timestamp == '2026-11-04T16:00:00',
    'Envelope decoding failed',
  );
  check(
    transport.requests.last.method == 'POST',
    'Method normalization failed',
  );
  check(
    jsonDecode(transport.requests.last.body!)['text'] == 'বাংলা',
    'JSON encoding failed',
  );
  check(
    transport.requests.last.headers['Authorization'] == 'Bearer first',
    'Missing bearer header',
  );
  token = 'second';
  await api.request('GET', 'users/me', authenticated: true, decode: (v) => v);
  check(
    transport.requests.last.headers['Authorization'] == 'Bearer second',
    'Stale bearer token',
  );
  await api.request('GET', 'lawyers/discover', decode: (v) => v);
  check(
    !transport.requests.last.headers.containsKey('Authorization'),
    'Public request leaked token',
  );
  print(
    'PASS typed envelopes, JSON requests, current bearer tokens, public requests',
  );

  transport.response = TransportResponse(
    statusCode: 400,
    body: jsonEncode({
      'success': false,
      'message': 'Validation failed',
      'data': {'email': 'Invalid email'},
    }),
  );
  final validation = await expectApiError(
    api.request('PUT', 'client/profile', decode: (v) => v),
    ApiErrorKind.validation,
  );
  check(
    validation.fieldErrors['email'] == 'Invalid email',
    'Lost field validation error',
  );
  for (final entry in {
    401: ApiErrorKind.unauthorized,
    403: ApiErrorKind.forbidden,
    404: ApiErrorKind.notFound,
    409: ApiErrorKind.conflict,
    429: ApiErrorKind.rateLimited,
    503: ApiErrorKind.server,
  }.entries) {
    transport.response = TransportResponse(
      statusCode: entry.key,
      body: '<html>Proxy error</html>',
    );
    final error = await expectApiError(
      api.request('GET', 'test', decode: (v) => v),
      entry.value,
    );
    check(!error.message.contains('<html>'), 'Exposed proxy HTML');
  }
  print('PASS validation fields and HTTP error mapping');

  for (final body in [
    'not json',
    '[]',
    '{"success":true}',
    '{"success":true,"message":"OK","data":null,"timestamp":123}',
    '{"success":false,"message":"Rejected","data":null}',
  ]) {
    transport.response = TransportResponse(statusCode: 200, body: body);
    await expectApiError(
      api.request('GET', 'test', decode: (v) => v),
      ApiErrorKind.invalidResponse,
    );
  }
  transport.response = const TransportResponse(
    statusCode: 200,
    body: '{"success":true,"message":"OK","data":"wrong type"}',
  );
  await expectApiError(
    api.request<int>('GET', 'test', decode: (v) => v as int),
    ApiErrorKind.invalidResponse,
  );
  print(
    'PASS malformed envelopes, application rejection, typed decoder failures',
  );

  for (final key in ['number', 'page']) {
    final page = ApiPage<int>.fromJson({
      'content': [1, 2],
      key: 0,
      'size': 2,
      'totalElements': 3,
      'totalPages': 2,
    }, (v) => v as int);
    check(page.hasNext && page.content.length == 2, 'Pagination failed');
  }
  print('PASS Spring and notification pagination');

  final unauthenticated = ApiClient(config: config, transport: _Transport());
  await expectApiError(
    unauthenticated.request(
      'GET',
      'users/me',
      authenticated: true,
      decode: (v) => v,
    ),
    ApiErrorKind.unauthorized,
  );
  unauthenticated.close();
  api.close();
  check(transport.closed, 'Transport was not closed');
  var rejected = false;
  try {
    await api.request('GET', 'test', decode: (v) => v);
  } on StateError {
    rejected = true;
  }
  check(rejected, 'Closed client accepted a request');
  print('PASS missing authentication and disposal');
}
