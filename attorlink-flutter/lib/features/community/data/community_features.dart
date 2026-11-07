import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import '../../auth/domain/auth_models.dart';
import '../domain/community_extras.dart';
import 'community_repository.dart';

const _validation = ApiException(
  kind: ApiErrorKind.validation,
  message: 'Check the supplied fields and try again.',
);

extension CommunityFeatures on CommunityRepository {
  Future<ApiPage<T>> _page<T>(
    String path,
    int page,
    T Function(Object?) decode,
  ) => withAccess(() async {
    if (page < 0) {
      throw _validation;
    }
    return (await api.request(
      'GET',
      path,
      authenticated: true,
      accessGuard: checkAccess,
      query: {'page': '$page', 'size': '10'},
      decode: (value) {
        final result = ApiPage.fromJson(value, decode);
        if (result.page != page || result.size != 10) {
          throw const FormatException('Unexpected page');
        }
        return result;
      },
    )).data;
  });

  Future<ApiPage<CommunityComment>> comments(
    int postId, {
    int? parentId,
    int page = 0,
  }) => _page(
    'community/posts/$postId/comments${parentId == null ? '' : '/$parentId/replies'}',
    page,
    (value) {
      final comment = CommunityComment.fromJson(value);
      if (comment.postId != postId ||
          (parentId != null && comment.parentId != parentId)) {
        throw const FormatException('Unexpected comment thread');
      }
      return comment;
    },
  );

  Future<CommunityComment> writeComment(
    int postId,
    String text, {
    CommunityComment? editing,
    int? parentId,
  }) => withAccess(() async {
    if (text.trim().isEmpty || text.length > 5000) {
      throw const ApiException(
        kind: ApiErrorKind.validation,
        message: 'Enter comment text of at most 5000 characters.',
      );
    }
    if (editing != null &&
        (editing.authorId != ownerId || editing.postId != postId)) {
      throw const ApiException(
        kind: ApiErrorKind.forbidden,
        message: 'Only the author can edit this comment.',
      );
    }
    return (await api.request(
      editing == null ? 'POST' : 'PATCH',
      editing != null
          ? 'community/comments/${editing.id}'
          : 'community/posts/$postId/comments${parentId == null ? '' : '/$parentId/replies'}',
      authenticated: true,
      accessGuard: checkAccess,
      body: {'text': text},
      decode: (value) {
        final comment = CommunityComment.fromJson(value);
        if (comment.postId != postId ||
            (editing != null && comment.id != editing.id) ||
            (editing == null && comment.parentId != parentId) ||
            (editing != null && comment.parentId != editing.parentId) ||
            comment.authorId != ownerId) {
          throw const FormatException('Unexpected saved comment');
        }
        return comment;
      },
    )).data;
  }, mutation: true);

  Future<void> deleteComment(CommunityComment comment) => withAccess(() async {
    if (comment.authorId != ownerId) {
      throw const ApiException(
        kind: ApiErrorKind.forbidden,
        message: 'Only the author can delete this comment.',
      );
    }
    await api.request(
      'DELETE',
      'community/comments/${comment.id}',
      authenticated: true,
      accessGuard: checkAccess,
      decode: (_) => null,
    );
  }, mutation: true);

  Future<CommunityComment> voteComment(
    CommunityComment comment,
    String? vote,
  ) => withAccess(() async {
    if (vote != null && !['UPVOTE', 'DOWNVOTE'].contains(vote)) {
      throw _validation;
    }
    // Selecting the current vote removes it explicitly; PUT also toggles on the server.
    final remove = vote == null || comment.vote == vote;
    return (await api.request(
      remove ? 'DELETE' : 'PUT',
      'community/comments/${comment.id}/vote',
      authenticated: true,
      accessGuard: checkAccess,
      body: remove ? null : {'voteType': vote},
      decode: (value) {
        final result = CommunityComment.fromJson(value);
        if (result.id != comment.id || result.postId != comment.postId) {
          throw const FormatException('Unexpected vote result');
        }
        return result;
      },
    )).data;
  }, mutation: true);

  void _client() {
    if (checkAccess().role != UserRole.client) {
      throw const ApiException(
        kind: ApiErrorKind.forbidden,
        message: 'Only clients may follow lawyers.',
      );
    }
  }

  Future<LawyerConnection> followLawyer(int lawyerUserId) =>
      withAccess(() async {
        _client();
        if (lawyerUserId <= 0 || lawyerUserId == ownerId) {
          throw _validation;
        }
        return (await api.request(
          'PUT',
          'community/lawyers/$lawyerUserId/follow',
          authenticated: true,
          accessGuard: checkAccess,
          decode: (value) {
            final follow = LawyerConnection.fromJson(value);
            if (follow.lawyerId != lawyerUserId ||
                follow.followerId != ownerId ||
                follow.id == null) {
              throw const FormatException('Unexpected follow');
            }
            return follow;
          },
        )).data;
      }, mutation: true);
  Future<void> unfollowLawyer(int lawyerUserId) => withAccess(() async {
    _client();
    if (lawyerUserId <= 0 || lawyerUserId == ownerId) {
      throw _validation;
    }
    // Controller returns a message-only envelope, even though its service returns a DTO.
    await api.request(
      'DELETE',
      'community/lawyers/$lawyerUserId/follow',
      authenticated: true,
      accessGuard: checkAccess,
      decode: (_) => null,
    );
  }, mutation: true);
  Future<ApiPage<LawyerConnection>> connections({
    int? lawyerUserId,
    int page = 0,
  }) {
    if (lawyerUserId == null) {
      _client();
    } else if (lawyerUserId <= 0) {
      throw _validation;
    }
    return _page(
      lawyerUserId == null
          ? 'community/following'
          : 'community/lawyers/$lawyerUserId/followers',
      page,
      (value) {
        final follow = LawyerConnection.fromJson(value);
        if (lawyerUserId == null
            ? follow.followerId != ownerId
            : follow.lawyerId != lawyerUserId) {
          throw const FormatException('Unexpected connection');
        }
        return follow;
      },
    );
  }

  Future<ReportReceipt> report({
    required String targetType,
    required int targetId,
    required String reason,
    String? explanation,
    int? authorId,
  }) => withAccess(() async {
    if (!reportTargets.contains(targetType) ||
        !reportReasons.contains(reason) ||
        targetId <= 0 ||
        (explanation?.length ?? 0) > 1000) {
      throw _validation;
    }
    if (authorId == ownerId) {
      throw const ApiException(
        kind: ApiErrorKind.forbidden,
        message: 'You cannot report your own content.',
      );
    }
    return (await api.request(
      'POST',
      'community/reports',
      authenticated: true,
      accessGuard: checkAccess,
      body: {
        'targetType': targetType,
        'targetId': targetId,
        'reason': reason,
        'explanation': ?explanation,
      },
      decode: (value) {
        final receipt = ReportReceipt.fromJson(value);
        if (receipt.targetType != targetType ||
            receipt.targetId != targetId ||
            receipt.reason != reason ||
            receipt.reporterId != ownerId) {
          throw const FormatException('Unexpected report receipt');
        }
        return receipt;
      },
    )).data;
  });

  Future<void> recordFeedEvent(
    int postId,
    String eventType, {
    String? feedMode,
  }) => withAccess(() async {
    if (postId <= 0 ||
        !feedEventTypes.contains(eventType) ||
        (feedMode != null &&
            ![
              'FOR_YOU',
              'FOLLOWING',
              'LATEST',
              'TRENDING',
            ].contains(feedMode))) {
      throw _validation;
    }
    await api.request(
      'POST',
      'community/feed-events',
      authenticated: true,
      accessGuard: checkAccess,
      body: {'postId': postId, 'eventType': eventType, 'feedMode': ?feedMode},
      decode: (_) => null,
    );
  });

  /// Tracking errors never turn a successful content mutation into a failed one.
  Future<String?> trackEvent(int postId, String event, {String? mode}) async {
    try {
      await recordFeedEvent(postId, event, feedMode: mode);
      return null;
    } on ApiException catch (error) {
      return 'Engagement tracking: ${error.message}';
    }
  }

  Future<CommunityAnalytics> analytics(int postId, String from, String to) =>
      withAccess(() async {
        if (postId <= 0 || localMoment(from).compareTo(localMoment(to)) >= 0) {
          throw const ApiException(
            kind: ApiErrorKind.validation,
            message: 'Choose a valid start time before the end time.',
          );
        }
        return (await api.request(
          'GET',
          'community/feed-analytics',
          authenticated: true,
          accessGuard: checkAccess,
          query: {'postId': '$postId', 'from': from, 'to': to},
          decode: (value) {
            final summary = CommunityAnalytics.fromJson(value);
            if (summary.postId != postId) {
              throw const FormatException('Unexpected analytics post');
            }
            return summary;
          },
        )).data;
      });
}

/// Validate LocalDateTime without timezone conversion or loss of nanoseconds.
String localMoment(String value) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?$',
  ).firstMatch(value);
  if (match == null) {
    throw const ApiException(
      kind: ApiErrorKind.validation,
      message:
          'Use a local date/time: YYYY-MM-DDTHH:MM:SS, without a timezone.',
    );
  }
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
  final date = DateTime.utc(
    parts[0],
    parts[1],
    parts[2],
    parts[3],
    parts[4],
    parts[5],
  );
  if ([
        date.year,
        date.month,
        date.day,
        date.hour,
        date.minute,
        date.second,
      ].join(',') !=
      parts.join(',')) {
    throw _validation;
  }
  return '${value.split('.').first}.${(match.group(7) ?? '').padRight(9, '0')}';
}
