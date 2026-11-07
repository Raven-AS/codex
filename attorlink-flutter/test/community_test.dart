import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attorlink_flutter/app/app_shell.dart';
import 'package:attorlink_flutter/core/config/api_config.dart';
import 'package:attorlink_flutter/core/network/api_client.dart';
import 'package:attorlink_flutter/core/network/api_exception.dart';
import 'package:attorlink_flutter/core/network/http_transport.dart';
import 'package:attorlink_flutter/features/auth/domain/auth_models.dart';
import 'package:attorlink_flutter/features/client/domain/client_photo.dart';
import 'package:attorlink_flutter/features/community/data/community_repository.dart';
import 'package:attorlink_flutter/features/community/domain/community_models.dart';
import 'package:attorlink_flutter/features/community/presentation/community_screen.dart';
import 'package:attorlink_flutter/features/community/presentation/post_editor.dart';

// Fixture responses are confined to tests, never used by the application.
Map<String, Object?> postJson({
  int id = 1,
  int author = 7,
  bool liked = false,
}) => {
  'id': id,
  'authorId': author,
  'type': 'TEXT',
  'textContent': 'Post $id',
  'deleted': false,
  'createdAt': '2026-11-04T12:00:00',
  'updatedAt': null,
  'mediaUrl': null,
  'mediaPublicId': null,
  'likeCount': 4,
  'currentUserLiked': liked,
  'sponsored': false,
};
Map<String, Object?> pageJson(
  List<Object?> posts, {
  int page = 0,
  int pages = 1,
}) => {
  'content': posts,
  'page': page,
  'size': 20,
  'totalElements': 21,
  'totalPages': pages,
};
TransportResponse ok(Object? data) => TransportResponse(
  statusCode: 200,
  body: jsonEncode({'success': true, 'message': 'Success', 'data': data}),
);

class Transport implements HttpTransport {
  Transport(this.handler);
  final FutureOr<TransportResponse> Function(TransportRequest) handler;
  final requests = <TransportRequest>[];
  @override
  Future<TransportResponse> send(TransportRequest request) async {
    requests.add(request);
    return handler(request);
  }

  @override
  void close() {}
}

const client = AuthUser(
  id: 7,
  email: 'test@example.invalid',
  role: UserRole.client,
  status: UserStatus.active,
);
CommunityRepository repository(
  Transport transport, {
  AuthUser? Function()? user,
}) => CommunityRepository(
  ApiClient(
    config: ApiConfig(baseUrl: Uri.parse('https://example.test/api/v1/')),
    transport: transport,
    accessTokenProvider: () => 'test-token',
  ),
  ownerId: 7,
  currentUser: user ?? () => client,
);
final forbidden = isA<ApiException>().having(
  (e) => e.kind,
  'kind',
  ApiErrorKind.forbidden,
);

void main() {
  test(
    'all feed categories use exact authenticated contracts and role guards',
    () async {
      AuthUser? current = client;
      final transport = Transport(
        (_) => ok(pageJson([postJson()], page: 2, pages: 4)),
      );
      final repo = repository(transport, user: () => current);
      for (final category in CommunityCategory.values) {
        final page = await repo.list(category, page: 2);
        final request = transport.requests.last;
        expect(request.method, 'GET');
        expect(request.headers['Authorization'], 'Bearer test-token');
        expect(
          request.uri.path,
          '/api/v1/${category.mode != null
              ? 'community/feed'
              : category == CommunityCategory.bookmarks
              ? 'community/bookmarks'
              : 'community/posts'}',
        );
        expect(request.uri.queryParameters, {
          'page': '2',
          'size': '20',
          if (category.mode != null) 'mode': category.mode!,
        });
        expect(page.content.single.authorId, 7);
        expect(page.content.single.likeCount, 4);
        expect(page.hasNext, isTrue);
      }
      current = const AuthUser(
        id: 7,
        email: 'lawyer@example.invalid',
        role: UserRole.lawyer,
        status: UserStatus.active,
      );
      await expectLater(
        repo.list(CommunityCategory.following),
        throwsA(forbidden),
      );
      current = null;
      await expectLater(
        repo.list(CommunityCategory.latest),
        throwsA(forbidden),
      );
      expect(transport.requests, hasLength(7));
    },
  );

  test('community image ownership upload, text/image saves, PATCH and delete match backend', () async {
    final transport = Transport((request) {
      if (request.uri.path.endsWith('/media')) {
        return ok({
          'url': 'https://example.test/image.png',
          'publicId': 'community/asset',
          'resourceType': 'image',
        });
      }
      if (request.method == 'DELETE') return ok(null);
      return ok(postJson());
    });
    final repo = repository(transport);
    final photo = ClientPhoto.fromBytes(
      'image.png',
      Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
    );
    final media = await repo.upload(photo);
    expect(transport.requests.single.uri.path, '/api/v1/community/posts/media');
    expect(
      transport.requests.single.headers['Content-Type'],
      startsWith('multipart/form-data; boundary='),
    );
    expect(
      utf8.decode(transport.requests.single.bodyBytes!, allowMalformed: true),
      contains('name="file"'),
    );
    await repo.create(type: 'IMAGE', text: '', mediaPublicId: media.publicId);
    expect(jsonDecode(transport.requests.last.body!), {
      'type': 'IMAGE',
      'text': '',
      'mediaPublicId': 'community/asset',
    });
    await repo.create(type: 'TEXT', text: 'Real text');
    expect(jsonDecode(transport.requests.last.body!), {
      'type': 'TEXT',
      'text': 'Real text',
    });
    final post = CommunityPost.fromJson(postJson());
    await repo.update(post, text: 'Edited', mediaPublicId: media.publicId);
    expect(transport.requests.last.method, 'PATCH');
    expect(jsonDecode(transport.requests.last.body!), {
      'text': 'Edited',
      'mediaPublicId': 'community/asset',
    });
    await repo.delete(post);
    expect(transport.requests.last.method, 'DELETE');
    expect(transport.requests.last.uri.path, '/api/v1/community/posts/1');
    for (final action in [
      () => repo.create(type: 'TEXT', text: ' '),
      () => repo.create(type: 'IMAGE', text: ''),
      () => repo.create(type: 'VIDEO', text: 'No'),
    ]) {
      await expectLater(action(), throwsA(isA<ApiException>()));
    }
    expect(
      () =>
          repo.update(CommunityPost.fromJson(postJson(author: 8)), text: 'No'),
      throwsA(forbidden),
    );
    expect(transport.requests, hasLength(5));
  });

  test('like toggle, unlike, explicit save/remove and share use server results without replay', () async {
    final transport = Transport(
      (request) => ok(
        request.uri.path.endsWith('/share')
            ? {'id': 9, 'postId': 1, 'createdAt': '2026-11-04T12:00:00'}
            : postJson(liked: request.method == 'PUT'),
      ),
    );
    final repo = repository(transport);
    final liked = await repo.like(CommunityPost.fromJson(postJson()));
    expect(liked.liked, isTrue);
    await repo.like(liked);
    await repo.save(1, saved: true);
    await repo.save(1, saved: false);
    expect((await repo.share(1)).postId, 1);
    expect(transport.requests.map((r) => '${r.method} ${r.uri.path}'), [
      'PUT /api/v1/community/posts/1/like',
      'DELETE /api/v1/community/posts/1/like',
      'PUT /api/v1/community/posts/1/bookmark',
      'DELETE /api/v1/community/posts/1/bookmark',
      'POST /api/v1/community/posts/1/share',
    ]);
    final failure = Transport(
      (_) => throw const ApiException(
        kind: ApiErrorKind.network,
        message: 'Offline',
      ),
    );
    await expectLater(
      repository(failure).like(liked),
      throwsA(isA<ApiException>()),
    );
    expect(failure.requests, hasLength(1));
  });

  testWidgets(
    'own posts paginate visible records and community state survives tab navigation',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(700, 1100);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final transport = Transport((request) {
        if (request.uri.path.endsWith('/feed-events')) return ok(null);
        if (request.uri.path.endsWith('/feed')) return ok(pageJson([]));
        final page = int.parse(request.uri.queryParameters['page']!);
        return ok(
          pageJson(
            [postJson(id: page + 1, author: page == 0 ? 8 : 7)],
            page: page,
            pages: 2,
          ),
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: AppShell(
            community: CommunityScreen(repository: repository(transport)),
          ),
        ),
      );
      expect(transport.requests, isEmpty);
      await tester.tap(find.text('Community'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('My posts'));
      await tester.pumpAndSettle();
      expect(find.text('Author ID 8'), findsNothing);
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(find.text('Post 2'), findsOneWidget);
      final count = transport.requests.length;
      await tester.tap(find.text('Messages'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Community').last);
      await tester.pumpAndSettle();
      expect(find.text('Post 2'), findsOneWidget);
      expect(transport.requests, hasLength(count));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editor validates before sending and blocks repeat of an ambiguous create',
    (tester) async {
      final transport = Transport(
        (_) => throw const ApiException(
          kind: ApiErrorKind.network,
          message: 'Offline',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CommunityPostEditor(repository: repository(transport)),
        ),
      );
      await tester.ensureVisible(find.text('Save post'));
      await tester.tap(find.text('Save post'));
      await tester.pumpAndSettle();
      expect(transport.requests, isEmpty);
      expect(find.textContaining('Text posts need text'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Text to submit');
      await tester.ensureVisible(find.text('Save post'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save post'));
      await tester.pumpAndSettle();
      expect(find.text('Offline'), findsOneWidget);
      expect(transport.requests, hasLength(1));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save post'),
            )
            .onPressed,
        isNull,
      );
    },
  );
}
