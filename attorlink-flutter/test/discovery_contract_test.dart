import 'package:flutter_test/flutter_test.dart';
import 'package:attorlink_flutter/core/config/api_config.dart';
import 'package:attorlink_flutter/core/network/api_client.dart';
import 'package:attorlink_flutter/core/network/api_exception.dart';
import 'package:attorlink_flutter/features/discovery/data/discovery_repository.dart';

import 'support/discovery_fixtures.dart';

void main() {
  test(
    'public GET uses only audited search/filter/page query and no bearer',
    () async {
      final transport = DiscoveryTransport(
        (request) => discoveryResponse(
          discoveryPage([discoveryLawyer(1)], page: 2, pages: 4),
        ),
      );
      var refreshes = 0;
      final api = ApiClient(
        config: ApiConfig(baseUrl: Uri.parse('https://example.test/api/v1/')),
        transport: transport,
        accessTokenProvider: () => 'owner-token',
        beforeAuthenticatedRequest: () async {
          refreshes++;
        },
      );
      addTearDown(api.close);
      final result = await DiscoveryRepository(api)
          .search(search: '  A & B%_  ', practiceAreaId: 7, page: 2);
      final request = transport.requests.single;
      expect(request.method, 'GET');
      expect(request.uri.path, '/api/v1/lawyers/discover');
      expect(request.uri.queryParameters, {
        'search': 'A & B%_',
        'practiceAreaId': '7',
        'page': '2',
        'size': '20',
      });
      expect(request.headers.containsKey('Authorization'), isFalse);
      expect(request.body, isNull);
      expect(refreshes, 0);
      expect(result.page, 2);
      expect(result.hasNext, isTrue);
      final lawyer = result.content.single;
      expect(lawyer.id, 1);
      expect(lawyer.userId, 101);
      expect(lawyer.fullName, 'Lawyer 1');
      expect(lawyer.professionalTitle, 'Advocate');
      expect(lawyer.yearsOfExperience, 0);
      expect(lawyer.practiceAreas, ['Family Law']);
      expect(lawyer.updatedAt, '2026-11-04T12:30:00.123456');
      expect(() => lawyer.practiceAreas.add('Changed'), throwsUnsupportedError);
    },
  );

  test(
    'blank search/filter omitted; page size capped at backend maximum',
    () async {
      final transport = DiscoveryTransport(
        (_) => discoveryResponse(discoveryPage([], size: 50, pages: 0)),
      );
      final page = await discoveryRepository(transport)
          .search(search: ' \n ', size: 100);
      expect(transport.requests.single.uri.queryParameters, {
        'page': '0',
        'size': '50',
      });
      expect(page.content, isEmpty);
      expect(page.hasNext, isFalse);
    },
  );

  test('invalid request values fail before transport', () async {
    final transport = DiscoveryTransport(
      (_) => throw StateError('No request expected'),
    );
    final repository = discoveryRepository(transport);
    for (final future in [
      repository.search(page: -1),
      repository.search(size: 0),
      repository.search(practiceAreaId: 0),
    ]) {
      await expectLater(
        future,
        throwsA(
          isA<ApiException>().having(
            (error) => error.kind,
            'kind',
            ApiErrorKind.validation,
          ),
        ),
      );
    }
    expect(transport.requests, isEmpty);
  });

  test('nullable discovery fields and blank name are supported without invented data', () async {
    final json = discoveryLawyer(1)
      ..addAll({
        'fullName': '',
        'profilePhoto': null,
        'professionalTitle': null,
        'bio': null,
        'yearsOfExperience': null,
        'practiceAreas': <String>[],
        'updatedAt': null,
        'rating': 5,
      });
    final result = await discoveryRepository(
      DiscoveryTransport((_) => discoveryResponse(discoveryPage([json]))),
    ).search();
    final lawyer = result.content.single;
    expect(lawyer.displayName, 'Lawyer');
    expect(lawyer.bio, isNull);
    expect(lawyer.yearsOfExperience, isNull);
    expect(lawyer.practiceAreas, isEmpty);
  });

  test(
    'malformed records and mismatched pages become invalid-response errors',
    () async {
      for (final data in [
        discoveryPage([
          discoveryLawyer(1)..['practiceAreas'] = [4],
        ]),
        discoveryPage([discoveryLawyer(1)..['userId'] = '101']),
        discoveryPage([discoveryLawyer(1)..['yearsOfExperience'] = '7']),
        discoveryPage([], page: 3),
        discoveryPage([], size: 0),
        {'content': [], 'page': 0},
      ]) {
        final repository = discoveryRepository(
          DiscoveryTransport((_) => discoveryResponse(data)),
        );
        await expectLater(
          repository.search(),
          throwsA(
            isA<ApiException>().having(
              (error) => error.kind,
              'kind',
              ApiErrorKind.invalidResponse,
            ),
          ),
        );
      }
    },
  );

  test(
    'practice areas use the public reference endpoint and exact id/name fields',
    () async {
      final transport = DiscoveryTransport(
        (_) => discoveryResponse([
          {
            'id': 7,
            'name': 'Family Law',
            'description': null,
            'parentId': null,
            'icon': null,
            'active': true,
          },
        ]),
      );
      final areas = await discoveryRepository(transport).practiceAreas();
      expect(transport.requests.single.uri.path, '/api/v1/practice-areas');
      expect(transport.requests.single.uri.hasQuery, isFalse);
      expect(
        transport.requests.single.headers.containsKey('Authorization'),
        isFalse,
      );
      expect(areas.single.id, 7);
      expect(areas.single.name, 'Family Law');
    },
  );

  test(
    '401/403 public responses do not rotate or reject the owner session',
    () async {
      for (final status in [401, 403]) {
        var sessionChanges = 0;
        final transport = DiscoveryTransport(
          (_) => discoveryResponse(null, status: status),
        );
        final api = ApiClient(
          config: ApiConfig(baseUrl: Uri.parse('https://example.test/api/v1/')),
          transport: transport,
          accessTokenProvider: () => 'token',
          recoverAuthentication: (_) async {
            sessionChanges++;
            return true;
          },
          onSessionRejected: (_) async {
            sessionChanges++;
          },
        );
        addTearDown(api.close);
        await expectLater(
          DiscoveryRepository(api).search(),
          throwsA(
            isA<ApiException>().having(
              (error) => error.statusCode,
              'status',
              status,
            ),
          ),
        );
        expect(transport.requests, hasLength(1));
        expect(sessionChanges, 0);
      }
    },
  );
}
