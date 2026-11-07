import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attorlink_flutter/app/app_shell.dart';
import 'package:attorlink_flutter/core/network/http_transport.dart';
import 'package:attorlink_flutter/features/discovery/presentation/discovery_screen.dart';

import 'support/discovery_fixtures.dart';

bool catalog(TransportRequest request) =>
    request.uri.path.endsWith('practice-areas');
final areas = [
  {'id': 7, 'name': 'Family Law'},
];

Future<void> mount(WidgetTester tester, DiscoveryTransport transport) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(700, 1000);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DiscoveryScreen(repository: discoveryRepository(transport)),
      ),
    ),
  );
}

Future<void> top(WidgetTester tester) async {
  tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .jumpTo(0);
  await tester.pump();
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('loading and newer search ignore late old responses', (
    tester,
  ) async {
    final pending = Completer<TransportResponse>();
    final transport = DiscoveryTransport((request) {
      if (catalog(request)) return discoveryResponse(areas);
      if (request.uri.queryParameters['search'] == 'New') {
        return discoveryResponse(
          discoveryPage([discoveryLawyer(2, name: 'New lawyer')]),
        );
      }
      return pending.future;
    });
    await mount(tester, transport);
    await tester.pump();
    expect(find.text('Finding lawyers…'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('discovery-search')),
      ' New ',
    );
    await tester.tap(find.text('Search lawyers'));
    await tester.pumpAndSettle();
    expect(find.text('New lawyer'), findsOneWidget);
    pending.complete(
      discoveryResponse(
        discoveryPage([discoveryLawyer(1, name: 'Old lawyer')]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Old lawyer'), findsNothing);
    expect(find.text('New lawyer'), findsOneWidget);
  });

  testWidgets(
    'load more failure retains results, retries same page and deduplicates',
    (tester) async {
      var attempts = 0;
      final transport = DiscoveryTransport((request) {
        if (catalog(request)) return discoveryResponse(areas);
        if (request.uri.queryParameters['page'] == '0') {
          return discoveryResponse(
            discoveryPage([discoveryLawyer(1)], total: 21, pages: 2),
          );
        }
        attempts++;
        if (attempts == 1) return discoveryResponse(null, status: 403);
        return discoveryResponse(
          discoveryPage(
            [discoveryLawyer(1), discoveryLawyer(2)],
            page: 1,
            total: 21,
            pages: 2,
          ),
        );
      });
      await mount(tester, transport);
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Load more'));
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(find.text('Lawyer 1'), findsOneWidget);
      expect(find.text('Access denied'), findsOneWidget);
      await reveal(tester, find.text('Try again'));
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      await top(tester);
      expect(find.text('Lawyer 1'), findsOneWidget);
      await reveal(tester, find.text('Lawyer 2'));
      expect(find.text('Lawyer 2'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
      expect(attempts, 2);
      expect(
        transport.requests.where((r) => r.uri.queryParameters['page'] == '1'),
        hasLength(2),
      );
    },
  );

  testWidgets(
    'search/filter, summary and navigation preserve discovery state',
    (tester) async {
      final transport = DiscoveryTransport(
        (request) => catalog(request)
            ? discoveryResponse(areas)
            : discoveryResponse(
                discoveryPage([
                  discoveryLawyer(1, name: 'Ada')
                    ..['practiceAreas'] = ['Criminal Law'],
                ]),
              ),
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: AppShell(
            discovery: DiscoveryScreen(
              repository: discoveryRepository(transport),
            ),
          ),
        ),
      );
      expect(
        transport.requests,
        isEmpty,
      ); // Lazy loading until Discover is opened.
      await tester.tap(find.text('Discover'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('discovery-search')),
        'Ada',
      );
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Family Law').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Search lawyers'));
      await tester.pumpAndSettle();
      expect(transport.requests.last.uri.queryParameters, {
        'search': 'Ada',
        'practiceAreaId': '7',
        'page': '0',
        'size': '20',
      });
      await reveal(tester, find.text('View summary'));
      final requests = transport.requests.length;
      await tester.tap(find.text('View summary'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Public biography 1'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Profile updated: 2026-11-04T12:30:00.123456'),
        ),
        findsOneWidget,
      );
      expect(
        transport.requests,
        hasLength(requests),
      ); // No fabricated detail GET.
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Messages'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discover'));
      await tester.pumpAndSettle();
      expect(transport.requests, hasLength(requests));
      await top(tester);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('discovery-search')))
            .controller!
            .text,
        'Ada',
      );
      expect(find.text('Family Law'), findsOneWidget);
      tester.view.physicalSize = const Size(1200, 800);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(transport.requests, hasLength(requests));
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(transport.requests.last.uri.queryParameters, {
        'page': '0',
        'size': '20',
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'catalog failure retries independently; empty results remain usable',
    (tester) async {
      var references = 0;
      final transport = DiscoveryTransport((request) {
        if (catalog(request)) {
          references++;
          return references == 1
              ? discoveryResponse(null, status: 503)
              : discoveryResponse([]);
        }
        return discoveryResponse(discoveryPage([], pages: 0));
      });
      await mount(tester, transport);
      await tester.pumpAndSettle();
      expect(find.text('No lawyers found'), findsOneWidget);
      expect(find.text('Retry practice areas'), findsOneWidget);
      await tester.tap(find.text('Retry practice areas'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No practice areas are currently available.'),
        findsOneWidget,
      );
      expect(
        transport.requests.where((request) => !catalog(request)),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('forbidden listings retry without showing stale data', (
    tester,
  ) async {
    var searches = 0;
    final transport = DiscoveryTransport((request) {
      if (catalog(request)) return discoveryResponse([]);
      searches++;
      return searches == 1
          ? discoveryResponse(null, status: 403)
          : discoveryResponse(discoveryPage([]));
    });
    await mount(tester, transport);
    await tester.pumpAndSettle();
    expect(find.text('Access denied'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Access denied'), findsNothing);
    expect(find.text('No lawyers found'), findsOneWidget);
    expect(searches, 2);
  });
}
