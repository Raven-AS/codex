typedef JsonDecoder<T> = T Function(Object? value);

class ApiResponse<T> {
  const ApiResponse({
    required this.message,
    required this.data,
    this.timestamp,
  });
  final String message;
  final T data;
  // Backend LocalDateTime values carry no timezone; preserve their wire value.
  final String? timestamp;
}

/// Supports Spring Page and the backend's custom notification page shape.
class ApiPage<T> {
  ApiPage({
    required List<T> content,
    required this.page,
    required this.size,
    required this.totalElements,
    required this.totalPages,
  }) : content = List.unmodifiable(content);

  factory ApiPage.fromJson(Object? value, JsonDecoder<T> decode) {
    if (value is! Map<String, dynamic> || value['content'] is! List) {
      throw const FormatException('Expected a paginated response');
    }
    int integer(String key, [String? fallback]) {
      final field = value[key] ?? (fallback == null ? null : value[fallback]);
      if (field is! int || field < 0) {
        throw FormatException('Invalid pagination field: $key');
      }
      return field;
    }

    return ApiPage(
      content: (value['content'] as List).map(decode).toList(),
      page: integer('number', 'page'),
      size: integer('size'),
      totalElements: integer('totalElements'),
      totalPages: integer('totalPages'),
    );
  }

  final List<T> content;
  final int page;
  final int size;
  final int totalElements;
  final int totalPages;
  bool get hasNext => page + 1 < totalPages;
}
