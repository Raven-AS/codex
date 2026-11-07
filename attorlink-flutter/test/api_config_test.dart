import 'package:flutter_test/flutter_test.dart';
import 'package:attorlink_flutter/core/config/api_config.dart';

void main() {
  test('normalizes API root and preserves URL encoded query values', () {
    final config = ApiConfig(baseUrl: Uri.parse('https://example.test/api/v1'));
    expect(
      config.endpoint('lawyers/discover', {'search': 'a/b & c'}).toString(),
      'https://example.test/api/v1/lawyers/discover?search=a%2Fb+%26+c',
    );
  });

  test('rejects invalid API roots and nonpositive timeout', () {
    for (final url in [
      'file:///tmp/api',
      'https://u:p@example.test',
      'https://example.test/?secret=x',
      'https://example.test/#fragment',
      '/api/v1',
    ]) {
      expect(() => ApiConfig(baseUrl: Uri.parse(url)), throwsArgumentError);
    }
    expect(
      () => ApiConfig(
        baseUrl: Uri.parse('https://example.test'),
        timeout: Duration.zero,
      ),
      throwsArgumentError,
    );
  });

  test('rejects absolute URLs, traversal and embedded query/fragment', () {
    final config = ApiConfig(
      baseUrl: Uri.parse('https://example.test/api/v1/'),
    );
    for (final path in [
      'https://other.test',
      '//other.test',
      '/users',
      '../admin',
      '%2e%2e/admin',
      '..%2fadmin',
      r'..\admin',
      'users?token=x',
      'users#x',
    ]) {
      expect(() => config.endpoint(path), throwsArgumentError, reason: path);
    }
  });
}
