import '../../auth/domain/auth_models.dart';
import '../../client/domain/client_models.dart' show optionalString;
import 'community_models.dart';

const reportReasons = [
  'SPAM',
  'HARASSMENT',
  'INAPPROPRIATE_CONTENT',
  'MISINFORMATION',
  'OTHER',
];
const reportTargets = ['POST', 'COMMENT'];
const feedEventTypes = [
  'FEED_IMPRESSION',
  'POST_CLICK',
  'POST_LIKE',
  'COMMENT_CREATED',
  'POST_SHARED',
  'POST_BOOKMARKED',
];

int? nullableId(Map<String, dynamic> json, String key) =>
    json[key] == null ? null : CommunityPost.positiveId(json, key);
int counter(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int || value < 0) {
    throw FormatException('Invalid $key');
  }
  return value;
}

class CommunityComment {
  CommunityComment.fromJson(Object? value) {
    final json = jsonObject(value);
    id = CommunityPost.positiveId(json, 'id');
    postId = nullableId(json, 'postId');
    parentId = nullableId(json, 'parentCommentId');
    authorId = nullableId(json, 'authorId');
    text = optionalString(json, 'text');
    createdAt = optionalString(json, 'createdAt');
    updatedAt = optionalString(json, 'updatedAt');
    deleted = CommunityPost.boolean(json, 'deleted');
    upvotes = counter(json, 'upvoteCount');
    downvotes = counter(json, 'downvoteCount');
    vote = optionalString(json, 'currentUserVote');
    if (vote != null && !['UPVOTE', 'DOWNVOTE'].contains(vote)) {
      throw const FormatException('Invalid vote');
    }
  }
  late final int id, upvotes, downvotes;
  late final int? postId, parentId, authorId;
  late final String? text, createdAt, updatedAt, vote;
  late final bool deleted;
}

class LawyerConnection {
  LawyerConnection.fromJson(Object? value) {
    final json = jsonObject(value);
    id = nullableId(json, 'id');
    followerId = nullableId(json, 'followerId');
    lawyerId = nullableId(json, 'lawyerId');
    createdAt = optionalString(json, 'createdAt');
  }
  late final int? id, followerId, lawyerId;
  late final String? createdAt;
}

class ReportReceipt {
  ReportReceipt.fromJson(Object? value) {
    final json = jsonObject(value);
    id = CommunityPost.positiveId(json, 'id');
    targetId = CommunityPost.positiveId(json, 'targetId');
    targetType = requiredString(json, 'targetType');
    reason = requiredString(json, 'reason');
    status = requiredString(json, 'status');
    if (!reportTargets.contains(targetType) ||
        !reportReasons.contains(reason) ||
        !['OPEN', 'IN_REVIEW', 'RESOLVED', 'REJECTED'].contains(status)) {
      throw const FormatException('Invalid report');
    }
    reporterId = nullableId(json, 'reporterId');
    explanation = optionalString(json, 'explanation');
    createdAt = optionalString(json, 'createdAt');
    updatedAt = optionalString(json, 'updatedAt');
  }
  late final int id, targetId;
  late final int? reporterId;
  late final String targetType, reason, status;
  late final String? explanation, createdAt, updatedAt;
}

class CommunityAnalytics {
  CommunityAnalytics.fromJson(Object? value) {
    final json = jsonObject(value);
    postId = CommunityPost.positiveId(json, 'postId');
    counts = Map.unmodifiable({
      for (final key in [
        'impressions',
        'clicks',
        'likes',
        'comments',
        'shares',
        'bookmarks',
      ])
        key: counter(json, key),
    });
    final rate = json['engagementRate'];
    if (rate is! num || !rate.isFinite || rate < 0) {
      throw const FormatException('Invalid engagementRate');
    }
    engagementRate = rate.toDouble();
    from = requiredString(json, 'windowStart');
    to = requiredString(json, 'windowEnd');
  }
  late final int postId;
  late final Map<String, int> counts;
  late final double engagementRate;
  late final String from, to;
}
