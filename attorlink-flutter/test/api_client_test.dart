import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:attorlink_flutter/core/config/api_config.dart';
import 'package:attorlink_flutter/core/network/api_client.dart';
import 'package:attorlink_flutter/core/network/api_exception.dart';
import 'package:attorlink_flutter/core/network/api_response.dart';
import 'package:attorlink_flutter/core/network/http_transport.dart';

class FakeTransport implements HttpTransport {
  FakeTransport(this.response);
  final TransportResponse response;
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

void main() {
  final config = ApiConfig(baseUrl: Uri.parse('https://example.test/api/v1'));
  FakeTransport response(
    Object? data, {
    bool success = true,
    int status = 200,
  }) => FakeTransport(
    TransportResponse(
      statusCode: status,
      body: jsonEncode({
        'success': success,
        'message': success ? 'Success' : 'Validation failed',
        'data': data,
        'timestamp': '2026-11-04T16:00:00',
      }),
    ),
  );

  test(
    'encodes query, JSON and bearer header using the current token',
    () async {
      final transport = response({'id': 7});
      var token = 'first';
      final client = ApiClient(
        config: config,
        transport: transport,
        accessTokenProvider: () => token,
      );
      addTearDown(client.close);
      final result = await client.request<int>(
        'post',
        'lawyers/discover',
        query: {'search': 'A & B'},
        body: {'text': 'বাংলা'},
        authenticated: true,
        decode: (data) => (data as Map)['id'] as int,
      );
      expect(result.data, 7);
      expect(result.timestamp, '2026-11-04T16:00:00');
      expect(transport.requests.single.uri.path, '/api/v1/lawyers/discover');
      expect(transport.requests.single.uri.queryParameters['search'], 'A & B');
      expect(transport.requests.single.method, 'POST');
      expect(jsonDecode(transport.requests.single.body!), {'text': 'বাংলা'});
      expect(
        transport.requests.single.headers['Authorization'],
        'Bearer first',
      );
      token = 'second';
      await client.request(
        'GET',
        'users/me',
        authenticated: true,
        decode: (v) => v,
      );
      expect(transport.requests.last.headers['Authorization'], 'Bearer second');
    },
  );

  test(
    'public requests omit tokens and null data supports message-only responses',
    () async {
      final transport = response(null);
      final client = ApiClient(
        config: config,
        transport: transport,
        accessTokenProvider: () => 'secret',
      );
      addTearDown(client.close);
      final result = await client.request<void>(
        'POST',
        'auth/signup',
        decode: (_) {},
      );
      expect(result.message, 'Success');
      expect(
        transport.requests.single.headers.containsKey('Authorization'),
        false,
      );
      expect(
        transport.requests.single.headers.containsKey('Content-Type'),
        false,
      );
    },
  );

  test(
    'missing bearer token prevents authenticated network requests',
    () async {
      final transport = response(null);
      final client = ApiClient(config: config, transport: transport);
      addTearDown(client.close);
      await expectLater(
        client.request(
          'GET',
          'users/me',
          authenticated: true,
          decode: (v) => v,
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiErrorKind.unauthorized,
          ),
        ),
      );
      expect(transport.requests, isEmpty);
    },
  );

  test(
    'retains backend validation messages without exposing non-string fields',
    () async {
      final client = ApiClient(
        config: config,
        transport: response(
          {'email': 'Invalid email', 'internal': 42},
          success: false,
          status: 400,
        ),
      );
      addTearDown(client.close);
      await expectLater(
        client.request('PUT', 'client/profile', decode: (v) => v),
        throwsA(
          isA<ApiException>()
              .having((e) => e.kind, 'kind', ApiErrorKind.validation)
              .having((e) => e.message, 'message', 'Validation failed')
              .having((e) => e.fieldErrors, 'fields', {
                'email': 'Invalid email',
              }),
        ),
      );
    },
  );

  for (final entry in {
    401: ApiErrorKind.unauthorized,
    403: ApiErrorKind.forbidden,
    404: ApiErrorKind.notFound,
    409: ApiErrorKind.conflict,
    429: ApiErrorKind.rateLimited,
    503: ApiErrorKind.server,
  }.entries) {
    test(
      'maps HTTP ${entry.key} with a non-JSON body to a safe error',
      () async {
        final client = ApiClient(
          config: config,
          transport: FakeTransport(
            TransportResponse(
              statusCode: entry.key,
              body: '<html>Proxy error</html>',
            ),
          ),
        );
        addTearDown(client.close);
        await expectLater(
          client.request('GET', 'test', decode: (v) => v),
          throwsA(
            isA<ApiException>()
                .having((e) => e.kind, 'kind', entry.value)
                .having((e) => e.message.contains('<html>'), 'no HTML', false),
          ),
        );
      },
    );
  }

  for (final body in [
    'not json',
    '[]',
    '{"success":true}',
    '{"success":true,"message":"OK","data":null,"timestamp":123}',
  ]) {
    test('rejects malformed success envelope: $body', () async {
      final client = ApiClient(
        config: config,
        transport: FakeTransport(
          TransportResponse(statusCode: 200, body: body),
        ),
      );
      addTearDown(client.close);
      await expectLater(
        client.request('GET', 'test', decode: (v) => v),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiErrorKind.invalidResponse,
          ),
        ),
      );
    });
  }

  test('rejects application failure even with HTTP 200', () async {
    final client = ApiClient(
      config: config,
      transport: response(null, success: false),
    );
    addTearDown(client.close);
    await expectLater(
      client.request('GET', 'test', decode: (v) => v),
      throwsA(isA<ApiException>()),
    );
  });

  test('normalizes typed data decoding failures', () async {
    final client = ApiClient(config: config, transport: response('wrong type'));
    addTearDown(client.close);
    await expectLater(
      client.request<int>('GET', 'test', decode: (v) => v as int),
      throwsA(
        isA<ApiException>().having(
          (e) => e.kind,
          'kind',
          ApiErrorKind.invalidResponse,
        ),
      ),
    );
  });

  test(
    'closing client closes transport and prevents further requests',
    () async {
      final transport = response(null);
      final client = ApiClient(config: config, transport: transport);
      client.close();
      client.close();
      expect(transport.closed, true);
      await expectLater(
        client.request('GET', 'test', decode: (v) => v),
        throwsStateError,
      );
    },
  );

  test('decodes Spring and custom page responses', () {
    for (final key in ['number', 'page']) {
      final page = ApiPage<int>.fromJson({
        'content': [1, 2],
        key: 0,
        'size': 2,
        'totalElements': 3,
        'totalPages': 2,
      }, (v) => v as int);
      expect(page.content, [1, 2]);
      expect(page.hasNext, true);
      expect(() => page.content.add(3), throwsUnsupportedError);
    }
    expect(
      () => ApiPage<int>.fromJson({'content': []}, (v) => v as int),
      throwsFormatException,
    );
  });
}
