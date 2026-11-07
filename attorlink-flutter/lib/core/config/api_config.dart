class ApiConfig {
  ApiConfig({required Uri baseUrl, this.timeout = const Duration(seconds: 30)})
    : baseUrl = _validate(baseUrl) {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive');
    }
  }

  factory ApiConfig.fromEnvironment({
    bool android = false,
    bool productionBuild = false,
  }) => ApiConfig.forRuntime(
    apiUrl: const String.fromEnvironment('ATTORLINK_API_URL'),
    environment: const String.fromEnvironment(
      'ATTORLINK_ENV',
      defaultValue: 'development',
    ),
    android: android,
    productionBuild: productionBuild,
  );

  factory ApiConfig.forRuntime({
    String apiUrl = '',
    String environment = 'development',
    bool android = false,
    bool productionBuild = false,
  }) {
    if (!['development', 'production'].contains(environment)) {
      throw ArgumentError('ATTORLINK_ENV must be development or production.');
    }
    final production = productionBuild || environment == 'production';
    if (production && apiUrl.trim().isEmpty) {
      throw ArgumentError(
        'Production requires an explicit HTTPS ATTORLINK_API_URL.',
      );
    }
    final url = apiUrl.trim().isNotEmpty
        ? apiUrl.trim()
        : android
        ? 'http://10.0.2.2:18081/api/v1/'
        : 'http://localhost:8081/api/v1/';
    final config = ApiConfig(baseUrl: Uri.parse(url));
    if (config.baseUrl.scheme == 'http' &&
        (production || !_localHost(config.baseUrl.host))) {
      throw ArgumentError(
        'HTTP is permitted only for local development. Use HTTPS for production.',
      );
    }
    return config;
  }

  static bool _localHost(String host) {
    if (host == 'localhost' || host == '::1') return true;
    final parts = host.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((p) => p == null || p < 0 || p > 255)) {
      return false;
    }
    return parts[0] == 127 ||
        parts[0] == 10 ||
        (parts[0] == 192 && parts[1] == 168) ||
        (parts[0] == 172 && parts[1]! >= 16 && parts[1]! <= 31);
  }

  final Uri baseUrl;
  final Duration timeout;

  static Uri _validate(Uri uri) {
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError.value(uri, 'baseUrl', 'Expected an HTTP(S) API URL');
    }
    return uri.replace(
      path: uri.path.endsWith('/') ? uri.path : '${uri.path}/',
    );
  }

  /// Paths are relative to the configured API root; callers cannot change hosts.
  Uri endpoint(String path, [Map<String, String>? query]) {
    final relative = Uri.parse(path);
    if (relative.hasScheme ||
        relative.hasAuthority ||
        relative.hasQuery ||
        relative.hasFragment ||
        relative.path.startsWith('/') ||
        relative.pathSegments.any(
          (part) =>
              part == '..' ||
              part == '.' ||
              part.contains('/') ||
              part.contains(r'\'),
        )) {
      throw ArgumentError.value(path, 'path', 'Expected a relative API path');
    }
    return baseUrl.resolveUri(relative).replace(queryParameters: query);
  }
}
