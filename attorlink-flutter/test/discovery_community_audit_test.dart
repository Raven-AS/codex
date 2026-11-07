import 'dart:async';
import 'dart:convert';

import 'package:attorlink_flutter/app/app_shell.dart';
import 'package:attorlink_flutter/core/config/api_config.dart';
import 'package:attorlink_flutter/core/network/api_client.dart';
import 'package:attorlink_flutter/core/network/api_exception.dart';
import 'package:attorlink_flutter/core/network/http_transport.dart';
import 'package:attorlink_flutter/features/community/data/community_features.dart';
import 'package:attorlink_flutter/features/community/data/community_repository.dart';
import 'package:attorlink_flutter/features/community/domain/community_extras.dart';
import 'package:attorlink_flutter/features/community/domain/community_models.dart';
import 'package:attorlink_flutter/features/community/presentation/community_screen.dart';
import 'package:attorlink_flutter/features/community/presentation/community_page_list.dart';
import 'package:attorlink_flutter/features/community/presentation/comment_screen.dart';
import 'package:attorlink_flutter/features/community/presentation/post_detail.dart';
import 'package:attorlink_flutter/features/community/presentation/post_editor.dart';
import 'package:attorlink_flutter/features/discovery/presentation/discovery_screen.dart';
import 'package:attorlink_flutter/features/discovery/presentation/lawyer_summary.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'community_features_test.dart' as comments;
import 'community_test.dart' as posts;
import 'support/discovery_fixtures.dart';

final _forbidden = throwsA(
  isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.forbidden),
);

Future<void> _mount(WidgetTester tester, Widget screen) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 1400);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: screen)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'replacing the community session clears old rows before the next read',
    (tester) async {
      final oldWire = posts.Transport(
        (r) => posts.ok(
          r.uri.path.endsWith('/feed-events')
              ? null
              : posts.pageJson([posts.postJson()]),
        ),
      );
      final delayed = Completer<TransportResponse>();
      final newWire = posts.Transport(
        (r) => r.uri.path.endsWith('/feed-events')
            ? posts.ok(null)
            : delayed.future,
      );
      final oldRepo = posts.repository(oldWire);
      final newRepo = posts.repository(newWire);
      addTearDown(oldRepo.api.close);
      addTearDown(newRepo.api.close);
      addTearDown(oldRepo.dispose);
      addTearDown(newRepo.dispose);
      var current = oldRepo;
      late StateSetter rebuild;
      await _mount(
        tester,
        StatefulBuilder(
          builder: (_, setState) {
            rebuild = setState;
            return CommunityScreen(repository: current);
          },
        ),
      );
      expect(find.text('Post 1'), findsOneWidget);
      rebuild(() => current = newRepo);
      await tester.pump();
      expect(find.text('Post 1'), findsNothing);
      delayed.complete(posts.ok(posts.pageJson([posts.postJson(id: 2)])));
      await tester.pumpAndSettle();
      expect(find.text('Post 2'), findsOneWidget);
    },
  );

  test('unavailable post reads invalidate cached community screens', () async {
    final wire = posts.Transport(
      (_) => const TransportResponse(
        statusCode: 404,
        body: '{"success":false,"message":"Post removed","data":null}',
      ),
    );
    final repo = posts.repository(wire);
    addTearDown(repo.api.close);
    addTearDown(repo.dispose);
    var invalidations = 0;
    repo.mutations.addListener(() {
      invalidations++;
    });
    await expectLater(repo.get(1), throwsA(isA<ApiException>()));
    expect(invalidations, 1);
  });

  testWidgets(
    'delete confirmation and reload callbacks cannot start duplicate operations',
    (tester) async {
      final delayed = Completer<TransportResponse>();
      var reads = 0;
      final wire = posts.Transport((r) {
        if (r.method == 'GET') {
          reads++;
          return reads == 1 ? posts.ok(posts.postJson()) : delayed.future;
        }
        return posts.ok(null);
      });
      final repo = posts.repository(wire);
      addTearDown(repo.api.close);
      addTearDown(repo.dispose);
      await _mount(tester, CommunityPostDetail(repository: repo, postId: 1));
      final delete = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Delete post'))
          .onPressed!;
      delete();
      delete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(wire.requests.where((r) => r.method == 'DELETE'), isEmpty);
      final reload = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Reload post'))
          .onPressed!;
      reload();
      reload();
      await tester.pump();
      expect(reads, 2);
      delayed.complete(posts.ok(posts.postJson()));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'a not-found vote clears stale comment rows and reloads the thread',
    (tester) async {
      var reads = 0;
      final wire = comments.Wire((r) {
        if (r.method == 'GET') {
          reads++;
          return comments.response(
            comments.page(reads == 1 ? [comments.comment()] : []),
          );
        }
        return comments.response(null, status: 404, message: 'Comment removed');
      });
      final repo = comments.repo(wire);
      addTearDown(repo.api.close);
      addTearDown(repo.dispose);
      await _mount(tester, CommunityComments(repository: repo, postId: 1));
      await tester.tap(find.text('Upvote'));
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.text('Comment 11'), findsNothing);
      expect(find.text('Comment removed'), findsOneWidget);
    },
  );

  testWidgets(
    'known profile changes refresh discovery without dropping the active query',
    (tester) async {
      var name = 'Original lawyer';
      var revision = 0;
      late StateSetter rebuild;
      final wire = DiscoveryTransport(
        (r) => discoveryResponse(
          r.uri.path.endsWith('/practice-areas')
              ? []
              : discoveryPage([discoveryLawyer(1, name: name)]),
        ),
      );
      final repo = discoveryRepository(wire);
      addTearDown(repo.api.close);
      await _mount(
        tester,
        StatefulBuilder(
          builder: (_, setState) {
            rebuild = setState;
            return DiscoveryScreen(repository: repo, refreshRevision: revision);
          },
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('discovery-search')),
        'Specific lawyer',
      );
      await tester.tap(find.text('Search lawyers'));
      await tester.pumpAndSettle();
      name = 'Updated lawyer';
      rebuild(() => revision++);
      await tester.pumpAndSettle();
      expect(find.text('Original lawyer'), findsNothing);
      expect(find.text('Updated lawyer'), findsOneWidget);
      expect(
        wire.requests.last.uri.queryParameters['search'],
        'Specific lawyer',
      );
    },
  );

  testWidgets(
    'community changes on a separate route invalidate the feed on return',
    (tester) async {
      var text = 'Old route text';
      var reads = 0;
      final wire = posts.Transport((r) {
        if (r.method == 'PATCH') {
          text = 'Changed through another route';
          return posts.ok({...posts.postJson(), 'textContent': text});
        }
        if (r.uri.path.endsWith('/feed-events')) return posts.ok(null);
        reads++;
        return posts.ok(
          posts.pageJson([
            {...posts.postJson(), 'textContent': text},
          ]),
        );
      });
      final repo = posts.repository(wire);
      addTearDown(repo.api.close);
      addTearDown(repo.dispose);
      await _mount(tester, CommunityScreen(repository: repo));
      final context = tester.element(find.byType(CommunityScreen));
      unawaited(
        Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Other route')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await repo.update(
        CommunityPost.fromJson(posts.postJson()),
        text: 'Changed',
      );
      await tester.pumpAndSettle();
      expect(reads, 1);
      if (!context.mounted) fail('Feed must remain mounted');
      Navigator.pop(context);
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.text('Changed through another route'), findsOneWidget);
    },
  );

  testWidgets(
    'comment pages reconcile votes and returned deleted rows by identity',
    (tester) async {
      final wire = comments.Wire((r) {
        final more = r.uri.queryParameters['page'] == '1';
        return comments.response(
          comments.page(
            more
                ? [
                    comments.comment(vote: 'UPVOTE'),
                    {...comments.comment(id: 12), 'deleted': true},
                    comments.comment(id: 13),
                  ]
                : [comments.comment(), comments.comment(id: 12)],
            number: more ? 1 : 0,
            pages: 2,
          ),
        );
      });
      final repo = comments.repo(wire);
      addTearDown(repo.api.close);
      addTearDown(repo.dispose);
      await _mount(
        tester,
        CommunityPageList<CommunityComment>(
          load: (page) => repo.comments(1, page: page),
          identity: (comment) => comment.id,
          retain: (comment) => !comment.deleted,
          item: (comment) => Text('${comment.id}: ${comment.vote}'),
        ),
      );
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(find.text('11: UPVOTE'), findsOneWidget);
      expect(find.text('11: null'), findsNothing);
      expect(find.text('12: null'), findsNothing);
      expect(find.text('13: null'), findsOneWidget);
    },
  );

  for (final operation in ['post', 'vote', 'follow', 'report']) {
    test(
      '$operation cannot use a replacement session after token refresh',
      () async {
        var generation = 1;
        final wire = posts.Transport((_) => throw StateError('Must not send'));
        final api = ApiClient(
          config: ApiConfig(baseUrl: Uri.parse('https://example.test/api/v1/')),
          transport: wire,
          accessTokenProvider: () => 'fixture-token',
          beforeAuthenticatedRequest: () async {
            generation++;
          },
        );
        final repo = CommunityRepository(
          api,
          ownerId: 7,
          currentUser: () => posts.client,
          sessionGeneration: () => generation,
        );
        addTearDown(api.close);
        addTearDown(repo.dispose);
        final Future<Object?> pending = switch (operation) {
          'post' => repo.create(type: 'TEXT', text: 'Fixture'),
          'vote' => repo.voteComment(
            CommunityComment.fromJson(comments.comment()),
            'UPVOTE',
          ),
          'follow' => repo.followLawyer(8),
          _ => repo.report(targetType: 'POST', targetId: 1, reason: 'SPAM'),
        };
        await expectLater(pending, _forbidden);
        expect(wire.requests, isEmpty);
      },
    );
  }

  test(
    '401 recovery never replays a community mutation for another session',
    () async {
      var generation = 1;
      final wire = posts.Transport(
        (_) => const TransportResponse(
          statusCode: 401,
          body: '{"success":false,"message":"Expired","data":null}',
        ),
      );
      final api = ApiClient(
        config: ApiConfig(baseUrl: Uri.parse('https://example.test/api/v1/')),
        transport: wire,
        accessTokenProvider: () => 'fixture-token',
        recoverAuthentication: (_) async {
          generation++;
          return true;
        },
      );
      final repo = CommunityRepository(
        api,
        ownerId: 7,
        currentUser: () => posts.client,
        sessionGeneration: () => generation,
      );
      addTearDown(api.close);
      addTearDown(repo.dispose);
      await expectLater(repo.share(1), _forbidden);
      expect(wire.requests, hasLength(1));
    },
  );

  test('mutations invalidate cached views; tracking does not trigger refresh loops', () async {
    final wire = posts.Transport((r) {
      if (r.uri.path.endsWith('/share')) {
        throw const ApiException(
          kind: ApiErrorKind.timeout,
          message: 'Fixture timeout',
        );
      }
      return posts.ok(
        r.uri.path.endsWith('/feed-events')
            ? null
            : posts.postJson(liked: true),
      );
    });
    final repo = posts.repository(wire);
    addTearDown(repo.api.close);
    addTearDown(repo.dispose);
    var changes = 0;
    repo.mutations.addListener(() {
      changes++;
    });
    await repo.like(CommunityPost.fromJson(posts.postJson()));
    expect(changes, 1);
    await repo.recordFeedEvent(1, 'POST_LIKE');
    expect(changes, 1);
    await expectLater(repo.share(1), throwsA(isA<ApiException>()));
    expect(changes, 2);
  });

  testWidgets('overlapping discovery pages adopt updated lawyer summaries', (
    tester,
  ) async {
    final wire = DiscoveryTransport((r) {
      if (r.uri.path.endsWith('/practice-areas')) return discoveryResponse([]);
      final more = r.uri.queryParameters['page'] == '1';
      return discoveryResponse(
        discoveryPage(
          more
              ? [discoveryLawyer(1, name: 'Updated lawyer'), discoveryLawyer(2)]
              : [discoveryLawyer(1, name: 'Old lawyer')],
          page: more ? 1 : 0,
          pages: 2,
          total: 2,
        ),
      );
    });
    final repo = discoveryRepository(wire);
    addTearDown(repo.api.close);
    await _mount(tester, DiscoveryScreen(repository: repo));
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(find.text('Old lawyer'), findsNothing);
    expect(find.text('Updated lawyer'), findsOneWidget);
    expect(find.byType(DiscoveryCard), findsNWidgets(2));
  });

  testWidgets(
    'overlapping feed pages replace edited rows and remove tombstones',
    (tester) async {
      final wire = posts.Transport((r) {
        if (r.uri.path.endsWith('/feed-events')) return posts.ok(null);
        final more = r.uri.queryParameters['page'] == '1';
        return posts.ok(
          posts.pageJson(
            more
                ? [
                    {...posts.postJson(), 'textContent': 'Updated text'},
                    {...posts.postJson(id: 3), 'deleted': true},
                    posts.postJson(id: 2),
                  ]
                : [posts.postJson(), posts.postJson(id: 3)],
            page: more ? 1 : 0,
            pages: 2,
          ),
        );
      });
      final repo = posts.repository(wire);
      addTearDown(repo.api.close);
      addTearDown(repo.dispose);
      await _mount(tester, CommunityScreen(repository: repo));
      final more = find.text('Load more');
      await tester.ensureVisible(more);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.text('Post 1'), findsNothing);
      expect(find.text('Post 3'), findsNothing);
      expect(find.text('Updated text'), findsOneWidget);
      expect(find.text('Post 2'), findsOneWidget);
    },
  );

  testWidgets(
    'a mutation outside the feed refreshes it when its tab becomes visible',
    (tester) async {
      var text = 'Original text';
      var reads = 0;
      final wire = posts.Transport((r) {
        if (r.method == 'PATCH') {
          text = jsonDecode(r.body!)['text'] as String;
          return posts.ok({...posts.postJson(), 'textContent': text});
        }
        if (r.uri.path.endsWith('/feed-events')) return posts.ok(null);
        reads++;
        return posts.ok(
          posts.pageJson([
            {...posts.postJson(), 'textContent': text},
          ]),
        );
      });
      final repo = posts.repository(wire);
      addTearDown(repo.api.close);
      addTearDown(repo.dispose);
      await _mount(
        tester,
        AppShell(
          initialDestination: AppDestination.community,
          community: CommunityScreen(repository: repo),
        ),
      );
      expect(reads, 1);
      final rail = find.byType(NavigationRail);
      await tester.tap(find.descendant(of: rail, matching: find.text('Home')));
      await tester.pumpAndSettle();
      await repo.update(
        CommunityPost.fromJson(posts.postJson()),
        text: 'External edit',
      );
      await tester.pumpAndSettle();
      expect(reads, 1);
      await tester.tap(
        find.descendant(of: rail, matching: find.text('Community')),
      );
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.text('External edit'), findsOneWidget);
      expect(find.text('Original text'), findsNothing);
    },
  );

  testWidgets(
    'rapid create callbacks send once and display backend field validation',
    (tester) async {
      final pending = Completer<TransportResponse>();
      final wire = posts.Transport((_) => pending.future);
      final repo = posts.repository(wire);
      addTearDown(repo.api.close);
      addTearDown(repo.dispose);
      await _mount(tester, CommunityPostEditor(repository: repo));
      await tester.enterText(find.byType(TextField), 'Fixture text');
      final save = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save post'))
          .onPressed!;
      save();
      save();
      await tester.pump();
      expect(wire.requests, hasLength(1));
      pending.complete(
        const TransportResponse(
          statusCode: 400,
          body: '{"success":false,"message":"Validation failed","data":{"text":"Fixture field feedback"}}',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Fixture field feedback'), findsOneWidget);
    },
  );

  testWidgets('unknown image-upload results cannot be blindly replayed', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = MethodChannel('attorlink/client-photo');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'name': 'fixture.png',
        'bytes': Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final wire = posts.Transport(
      (_) => throw const ApiException(
        kind: ApiErrorKind.network,
        message: 'Fixture lost response',
      ),
    );
    final repo = posts.repository(wire);
    addTearDown(repo.api.close);
    addTearDown(repo.dispose);
    await _mount(tester, CommunityPostEditor(repository: repo));
    await tester.tap(find.text('Choose and upload image'));
    await tester.pumpAndSettle();
    expect(wire.requests, hasLength(1));
    expect(find.textContaining('The upload result is unknown'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Choose and upload image'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save post'))
          .onPressed,
      isNotNull,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'discovery connection navigation uses lawyer user ID, not profile ID',
    (tester) async {
      final discoveryWire = DiscoveryTransport(
        (r) => discoveryResponse(
          r.uri.path.endsWith('/practice-areas')
              ? []
              : discoveryPage([discoveryLawyer(11)]),
        ),
      );
      final discovery = discoveryRepository(discoveryWire);
      final wire = posts.Transport((_) => comments.response(comments.page([])));
      final community = posts.repository(wire);
      addTearDown(discovery.api.close);
      addTearDown(community.api.close);
      addTearDown(community.dispose);
      await _mount(
        tester,
        DiscoveryScreen(repository: discovery, community: community),
      );
      await tester.tap(find.text('View summary'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lawyer connections'));
      await tester.pumpAndSettle();
      expect(
        wire.requests.single.uri.path,
        '/api/v1/community/lawyers/111/followers',
      );
      expect(find.text('Followers of lawyer user ID 111'), findsOneWidget);
    },
  );
}
