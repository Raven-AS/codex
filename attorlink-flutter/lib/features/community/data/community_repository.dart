import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import '../../auth/domain/auth_models.dart';
import '../../client/domain/client_photo.dart';
import '../domain/community_models.dart';

class CommunityRepository {
  CommunityRepository(
    this.api, {
    required this.ownerId,
    required this.currentUser,
    this.accessChanges,
    this.sessionGeneration,
  }) : _initialGeneration = sessionGeneration?.call();
  final ApiClient api;
  final int ownerId;
  final AuthUser? Function() currentUser;
  final Stream<Object?>? accessChanges;
  final int Function()? sessionGeneration;
  final int? _initialGeneration;
  final _mutations = ValueNotifier<int>(0);
  bool _disposed = false;
  ValueListenable<int> get mutations => _mutations;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _mutations.dispose();
  }

  AuthUser checkAccess() {
    final user = currentUser();
    if (_disposed ||
        sessionGeneration?.call() != _initialGeneration ||
        user == null ||
        user.id != ownerId ||
        user.status != UserStatus.active ||
        ![UserRole.client, UserRole.lawyer].contains(user.role)) {
      throw const ApiException(
        kind: ApiErrorKind.forbidden,
        message: 'An active client or lawyer account is required.',
      );
    }
    return user;
  }

  Future<T> _guard<T>(
    Future<T> Function() action, {
    bool mutation = false,
  }) async {
    checkAccess();
    try {
      final result = await action();
      checkAccess();
      if (mutation) _mutations.value++;
      return result;
    } on ApiException catch (error) {
      checkAccess();
      if (mutation &&
          (uncertainCommunityOperation(error) ||
              error.kind == ApiErrorKind.notFound ||
              error.kind == ApiErrorKind.forbidden)) {
        _mutations.value++;
      }
      rethrow;
    }
  }

  Future<T> withAccess<T>(
    Future<T> Function() action, {
    bool mutation = false,
  }) => _guard(action, mutation: mutation);

  Future<ApiPage<CommunityPost>> list(
    CommunityCategory category, {
    int page = 0,
  }) => _guard(() async {
    if (page < 0) throw ArgumentError.value(page);
    if (category == CommunityCategory.following &&
        checkAccess().role != UserRole.client) {
      throw const ApiException(
        kind: ApiErrorKind.forbidden,
        message: 'The Following feed is available to clients.',
      );
    }
    final path = category.mode != null
        ? 'community/feed'
        : category == CommunityCategory.bookmarks
        ? 'community/bookmarks'
        : 'community/posts';
    return (await api.request(
      'GET',
      path,
      authenticated: true,
      accessGuard: checkAccess,
      query: {
        if (category.mode != null) 'mode': category.mode!,
        'page': '$page',
        'size': '20',
      },
      decode: (value) {
        final result = ApiPage.fromJson(value, CommunityPost.fromJson);
        if (result.page != page || result.size != 20) {
          throw const FormatException('Unexpected community page');
        }
        return result;
      },
    )).data;
  });

  Future<CommunityPost> get(int id) async {
    try {
      return await _post('GET', id);
    } on ApiException catch (error) {
      checkAccess();
      if (error.kind == ApiErrorKind.notFound ||
          error.kind == ApiErrorKind.forbidden) {
        _mutations.value++;
      }
      rethrow;
    }
  }

  Future<CommunityPost> _post(
    String method,
    int id, {
    String suffix = '',
    Object? body,
  }) => _guard(() async {
    final response = await api.request(
      method,
      'community/posts/$id$suffix',
      authenticated: true,
      accessGuard: checkAccess,
      body: body,
      decode: (value) {
        final post = CommunityPost.fromJson(value);
        if (post.id != id || (method == 'PATCH' && post.authorId != ownerId)) {
          throw const FormatException('Unexpected post');
        }
        return post;
      },
    );
    return response.data;
  }, mutation: method != 'GET');

  Future<CommunityMedia> upload(ClientPhoto photo) => _guard(
    () async => (await api.request(
      'POST',
      'community/posts/media',
      authenticated: true,
      accessGuard: checkAccess,
      encodedBody: photo.multipart(),
      decode: CommunityMedia.fromJson,
    )).data,
  );

  static void validateText(
    String type,
    String text,
    String? mediaPublicId, {
    bool creating = true,
  }) {
    if (!['TEXT', 'IMAGE'].contains(type) ||
        text.length > 5000 ||
        (type == 'TEXT' && text.trim().isEmpty) ||
        (creating &&
            type == 'IMAGE' &&
            (mediaPublicId == null || mediaPublicId.trim().isEmpty))) {
      throw const ApiException(
        kind: ApiErrorKind.validation,
        message: 'Use text up to 5000 characters. Text posts need text; image posts need an uploaded image.',
      );
    }
  }

  Future<CommunityPost> create({
    required String type,
    required String text,
    String? mediaPublicId,
  }) => _guard(() async {
    validateText(type, text, mediaPublicId);
    return (await api.request(
      'POST',
      'community/posts',
      authenticated: true,
      accessGuard: checkAccess,
      body: {'type': type, 'text': text, 'mediaPublicId': ?mediaPublicId},
      decode: (value) {
        final post = CommunityPost.fromJson(value);
        if (post.authorId != ownerId) {
          throw const FormatException('Unexpected post author');
        }
        return post;
      },
    )).data;
  }, mutation: true);

  void _own(CommunityPost post) {
    checkAccess();
    if (post.authorId != ownerId) {
      throw const ApiException(
        kind: ApiErrorKind.forbidden,
        message: 'Only the author can manage this post.',
      );
    }
  }

  Future<CommunityPost> update(
    CommunityPost post, {
    required String text,
    String? mediaPublicId,
  }) {
    _own(post);
    validateText(post.type, text, mediaPublicId, creating: false);
    return _post(
      'PATCH',
      post.id,
      body: {'text': text, 'mediaPublicId': ?mediaPublicId},
    );
  }

  Future<void> delete(CommunityPost post) => _guard(() async {
    _own(post);
    await api.request(
      'DELETE',
      'community/posts/${post.id}',
      authenticated: true,
      accessGuard: checkAccess,
      decode: (_) => null,
    );
  }, mutation: true);

  // PUT like toggles on this backend; never retry an ambiguous outcome locally.
  Future<CommunityPost> like(CommunityPost post) =>
      _post(post.liked ? 'DELETE' : 'PUT', post.id, suffix: '/like');
  Future<CommunityPost> save(int id, {required bool saved}) =>
      _post(saved ? 'PUT' : 'DELETE', id, suffix: '/bookmark');
  Future<CommunityShare> share(int id) => _guard(
    () async => (await api.request(
      'POST',
      'community/posts/$id/share',
      authenticated: true,
      accessGuard: checkAccess,
      decode: (value) {
        final share = CommunityShare.fromJson(value);
        if (share.postId != id) {
          throw const FormatException('Unexpected shared post');
        }
        return share;
      },
    )).data,
    mutation: true,
  );
}
