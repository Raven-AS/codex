import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attorlink_flutter/core/config/api_config.dart';
import 'package:attorlink_flutter/core/network/api_client.dart';
import 'package:attorlink_flutter/core/network/api_exception.dart';
import 'package:attorlink_flutter/core/network/http_transport.dart';
import 'package:attorlink_flutter/features/auth/domain/auth_models.dart';
import 'package:attorlink_flutter/features/community/data/community_repository.dart';
import 'package:attorlink_flutter/features/community/data/community_features.dart';
import 'package:attorlink_flutter/features/community/domain/community_extras.dart';
import 'package:attorlink_flutter/features/community/presentation/comment_screen.dart';

// Test fixtures only. No production authentication or response is simulated.
Map<String, Object?> comment({
  int id = 11,
  int? parent,
  int author = 7,
  String? vote,
}) => {
  'id': id,
  'postId': 1,
  'parentCommentId': parent,
  'authorId': author,
  'text': 'Comment $id',
  'deleted': false,
  'createdAt': '2026-11-04T10:00:00',
  'updatedAt': null,
  'upvoteCount': 4,
  'downvoteCount': 2,
  'currentUserVote': vote,
};
Map<String, Object?> page(
  List<Object?> rows, {
  int number = 0,
  int pages = 1,
}) => {
  'content': rows,
  'page': number,
  'size': 10,
  'totalElements': rows.length,
  'totalPages': pages,
};
TransportResponse response(
  Object? data, {
  int status = 200,
  String message = 'Success',
}) => TransportResponse(
  statusCode: status,
  body: jsonEncode({
    'success': status == 200,
    'message': message,
    'data': data,
  }),
);

class Wire implements HttpTransport {
  Wire(this.handler);
  final FutureOr<TransportResponse> Function(TransportRequest) handler;
  final requests = <TransportRequest>[];
  @override
  Future<TransportResponse> send(TransportRequest r) async {
    requests.add(r);
    return handler(r);
  }

  @override
  void close() {}
}

const client = AuthUser(
  id: 7,
  email: 'fixture@example.invalid',
  role: UserRole.client,
  status: UserStatus.active,
);
CommunityRepository repo(Wire wire, {AuthUser? Function()? current}) =>
    CommunityRepository(
      ApiClient(
        config: ApiConfig(baseUrl: Uri.parse('https://example.test/api/v1/')),
        transport: wire,
        accessTokenProvider: () => 'fixture-token',
      ),
      ownerId: 7,
      currentUser: current ?? () => client,
    );

void main() {
  test(
    '5C comments: exact threads, CRUD and vote contracts with ownership guards',
    () async {
      final wire = Wire((r) {
        if (r.method == 'GET') {
          return response(
            page([comment(parent: r.uri.path.endsWith('/replies') ? 9 : null)]),
          );
        }
        if (r.method == 'DELETE' && !r.uri.path.endsWith('/vote')) {
          return response(null);
        }
        return response(
          comment(parent: r.uri.path.endsWith('/replies') ? 9 : null),
        );
      });
      final api = repo(wire);
      final root = (await api.comments(1)).content.single;
      expect(root.upvotes, 4);
      expect(root.downvotes, 2);
      expect(root.authorId, 7);
      await api.comments(1, parentId: 9);
      expect(
        wire.requests.last.uri.path,
        '/api/v1/community/posts/1/comments/9/replies',
      );
      expect(wire.requests.last.uri.queryParameters, {
        'page': '0',
        'size': '10',
      });
      await api.writeComment(1, 'Top level');
      expect(wire.requests.last.method, 'POST');
      expect(jsonDecode(wire.requests.last.body!), {'text': 'Top level'});
      await api.writeComment(1, 'Reply', parentId: 9);
      expect(
        wire.requests.last.uri.path,
        '/api/v1/community/posts/1/comments/9/replies',
      );
      await api.writeComment(1, 'Edit', editing: root);
      expect(wire.requests.last.method, 'PATCH');
      expect(wire.requests.last.uri.path, '/api/v1/community/comments/11');
      await api.voteComment(root, 'UPVOTE');
      expect(jsonDecode(wire.requests.last.body!), {'voteType': 'UPVOTE'});
      await api.voteComment(
        CommunityComment.fromJson(comment(vote: 'UPVOTE')),
        'UPVOTE',
      );
      expect(wire.requests.last.method, 'DELETE');
      expect(wire.requests.last.body, isNull);
      await api.voteComment(root, 'DOWNVOTE');
      expect(jsonDecode(wire.requests.last.body!), {'voteType': 'DOWNVOTE'});
      await api.deleteComment(root);
      expect(wire.requests.last.method, 'DELETE');
      final count = wire.requests.length;
      await expectLater(api.writeComment(1, ' '), throwsA(isA<ApiException>()));
      await expectLater(
        api.deleteComment(CommunityComment.fromJson(comment(author: 8))),
        throwsA(isA<ApiException>()),
      );
      expect(wire.requests, hasLength(count));
      expect(
        wire.requests.every(
          (r) => r.headers['Authorization'] == 'Bearer fixture-token',
        ),
        isTrue,
      );
    },
  );

  test('5C connections: lawyer user IDs, message-only unfollow, lists and client-only mutation', () async {
    AuthUser? user = client;
    final follow = {
      'id': 3,
      'followerId': 7,
      'lawyerId': 42,
      'createdAt': '2026-11-04T10:00:00',
    };
    final wire = Wire(
      (r) => response(
        r.method == 'GET'
            ? page([follow])
            : r.method == 'DELETE'
            ? null
            : follow,
      ),
    );
    final api = repo(wire, current: () => user);
    expect((await api.followLawyer(42)).lawyerId, 42);
    expect(wire.requests.last.uri.path, '/api/v1/community/lawyers/42/follow');
    await api.unfollowLawyer(42);
    expect(wire.requests.last.method, 'DELETE');
    await api.connections();
    expect(wire.requests.last.uri.path, '/api/v1/community/following');
    await api.connections(lawyerUserId: 42);
    expect(
      wire.requests.last.uri.path,
      '/api/v1/community/lawyers/42/followers',
    );
    user = const AuthUser(
      id: 7,
      email: 'lawyer@example.invalid',
      role: UserRole.lawyer,
      status: UserStatus.active,
    );
    await expectLater(
      api.followLawyer(42),
      throwsA(
        isA<ApiException>().having(
          (e) => e.kind,
          'kind',
          ApiErrorKind.forbidden,
        ),
      ),
    );
    await api.connections(
      lawyerUserId: 42,
    ); // Followers are not restricted to the viewing client.
    user = null;
    await expectLater(api.followLawyer(42), throwsA(isA<ApiException>()));
    expect(wire.requests, hasLength(5));
  });

  test('5C reports: exact targets/reasons, real receipts, own-content and duplicate errors', () async {
    final wire = Wire((r) {
      final body = jsonDecode(r.body!) as Map<String, dynamic>;
      return response({
        'id': 5,
        ...body,
        'status': 'OPEN',
        'reporterId': 7,
        'createdAt': '2026-11-04T10:00:00',
        'updatedAt': null,
      });
    });
    final api = repo(wire);
    for (final reason in reportReasons) {
      final receipt = await api.report(
        targetType: 'COMMENT',
        targetId: 11,
        reason: reason,
        explanation: 'Explanation',
        authorId: 8,
      );
      expect(receipt.status, 'OPEN');
      expect(receipt.reporterId, 7);
      expect(wire.requests.last.uri.path, '/api/v1/community/reports');
      expect(jsonDecode(wire.requests.last.body!), {
        'targetType': 'COMMENT',
        'targetId': 11,
        'reason': reason,
        'explanation': 'Explanation',
      });
    }
    await api.report(targetType: 'POST', targetId: 1, reason: 'SPAM');
    final count = wire.requests.length;
    await expectLater(
      api.report(targetType: 'POST', targetId: 1, reason: 'SPAM', authorId: 7),
      throwsA(isA<ApiException>()),
    );
    await expectLater(
      api.report(targetType: 'USER', targetId: 1, reason: 'SPAM'),
      throwsA(isA<ApiException>()),
    );
    expect(wire.requests, hasLength(count));
    final duplicate = Wire(
      (_) => response(
        null,
        status: 400,
        message: 'You have already reported this content with the same reason',
      ),
    );
    await expectLater(
      repo(duplicate).report(targetType: 'POST', targetId: 1, reason: 'SPAM'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('already reported'),
        ),
      ),
    );
    expect(duplicate.requests, hasLength(1));
  });

  test('5C analytics: nanosecond windows, returned metrics and event payloads without fabricated totals', () async {
    const from = '2026-11-04T10:00:00.000000001',
        to = '2026-11-04T10:00:00.000000002';
    final wire = Wire(
      (r) => response(
        r.method == 'POST'
            ? null
            : {
                'postId': 1,
                'impressions': 2,
                'clicks': 3,
                'likes': 4,
                'comments': 5,
                'shares': 6,
                'bookmarks': 7,
                'engagementRate': 1250.0,
                'windowStart': from,
                'windowEnd': to,
              },
      ),
    );
    final api = repo(wire);
    final summary = await api.analytics(1, from, to);
    expect(summary.counts['impressions'], 2);
    expect(summary.engagementRate, 1250);
    expect(wire.requests.last.uri.queryParameters, {
      'postId': '1',
      'from': from,
      'to': to,
    });
    for (final event in feedEventTypes) {
      await api.recordFeedEvent(1, event, feedMode: 'LATEST');
      expect(wire.requests.last.uri.path, '/api/v1/community/feed-events');
      expect(jsonDecode(wire.requests.last.body!), {
        'postId': 1,
        'eventType': event,
        'feedMode': 'LATEST',
      });
    }
    final count = wire.requests.length;
    await expectLater(api.analytics(1, to, from), throwsA(isA<ApiException>()));
    await expectLater(
      api.analytics(1, '2026-02-30T10:00:00', to),
      throwsA(isA<ApiException>()),
    );
    await expectLater(
      api.analytics(1, '2026-11-04T10:00:00Z', to),
      throwsA(isA<ApiException>()),
    );
    expect(wire.requests, hasLength(count));
    final failure = Wire(
      (_) => throw const ApiException(
        kind: ApiErrorKind.network,
        message: 'Offline',
      ),
    );
    expect(
      await repo(failure).trackEvent(1, 'POST_CLICK'),
      contains('Offline'),
    );
    expect(failure.requests, hasLength(1));
  });

  testWidgets(
    '5C replies show parent/author data, page correctly and respect server privacy failures',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(700, 1100);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final wire = Wire((r) {
        if (r.method == 'GET') {
          final number = int.parse(r.uri.queryParameters['page']!);
          return response(
            page(
              [comment(id: 12 + number, parent: 11, author: 8)],
              number: number,
              pages: 2,
            ),
          );
        }
        return response(
          null,
          status: 400,
          message: 'Only followers can comment on this post',
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: CommunityComments(
            repository: repo(wire),
            postId: 1,
            parentId: 11,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Reply to comment #11'), findsOneWidget);
      expect(find.textContaining('Author ID 8'), findsOneWidget);
      expect(find.text('Edit'), findsNothing);
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(find.text('Comment 13'), findsOneWidget);
      await tester.tap(find.text('Add reply'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save comment'));
      await tester.pumpAndSettle();
      expect(wire.requests.where((r) => r.method == 'POST'), isEmpty);
      await tester.enterText(find.byType(TextField), 'Reply text');
      await tester.tap(find.text('Save comment'));
      await tester.pumpAndSettle();
      expect(
        find.text('Only followers can comment on this post'),
        findsOneWidget,
      );
      expect(
        wire.requests.last.uri.path,
        '/api/v1/community/posts/1/comments/11/replies',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
