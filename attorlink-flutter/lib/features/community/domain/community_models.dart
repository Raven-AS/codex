import '../../../core/network/api_exception.dart';
import '../../auth/domain/auth_models.dart';
import '../../client/domain/client_models.dart' show optionalString;

enum CommunityCategory {
  forYou('For you', 'FOR_YOU'),
  following('Following', 'FOLLOWING'),
  latest('Latest', 'LATEST'),
  trending('Trending', 'TRENDING'),
  all('All posts', null),
  bookmarks('Saved posts', null),
  own('My posts', null);

  const CommunityCategory(this.label, this.mode);
  final String label;
  final String? mode;
}

class CommunityPost {
  CommunityPost.fromJson(Object? value) {
    final json = jsonObject(value);
    id = positiveId(json, 'id');
    authorId = json['authorId'] == null ? null : positiveId(json, 'authorId');
    type = requiredString(json, 'type');
    text = optionalString(json, 'textContent');
    mediaUrl = optionalString(json, 'mediaUrl');
    mediaPublicId = optionalString(json, 'mediaPublicId');
    createdAt = optionalString(json, 'createdAt');
    updatedAt = optionalString(json, 'updatedAt');
    deleted = boolean(json, 'deleted');
    liked = boolean(json, 'currentUserLiked');
    sponsored = boolean(json, 'sponsored');
    final count = json['likeCount'];
    if (count is! int || count < 0) {
      throw const FormatException('Invalid likeCount');
    }
    likeCount = count;
  }
  late final int id;
  late final int? authorId;
  late final String type;
  late final String? text, mediaUrl, mediaPublicId, createdAt, updatedAt;
  late final bool deleted, liked, sponsored;
  late final int likeCount;
  bool get editable => type == 'TEXT' || type == 'IMAGE';

  static int positiveId(Map<String, dynamic> json, String key) {
    final id = json[key];
    if (id is! int || id <= 0) throw FormatException('Invalid $key');
    return id;
  }

  static bool boolean(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! bool) throw FormatException('Invalid $key');
    return value;
  }
}

class CommunityMedia {
  CommunityMedia.fromJson(Object? value) {
    final json = jsonObject(value);
    url = requiredString(json, 'url');
    publicId = requiredString(json, 'publicId');
    if (json['resourceType'] != 'image') {
      throw const FormatException('Expected image upload');
    }
  }
  late final String url, publicId;
}

class CommunityShare {
  CommunityShare.fromJson(Object? value) {
    final json = jsonObject(value);
    id = CommunityPost.positiveId(json, 'id');
    postId = CommunityPost.positiveId(json, 'postId');
    createdAt = optionalString(json, 'createdAt');
  }
  late final int id, postId;
  late final String? createdAt;
}

bool uncertainCommunityOperation(ApiException error) => switch (error.kind) {
  ApiErrorKind.network ||
  ApiErrorKind.timeout ||
  ApiErrorKind.server ||
  ApiErrorKind.invalidResponse => true,
  _ => false,
};

/// Preserve field-level backend feedback even when it has no dedicated input.
String communityErrorMessage(ApiException error) =>
    [error.message, ...error.fieldErrors.values.toSet()].join('\n');
