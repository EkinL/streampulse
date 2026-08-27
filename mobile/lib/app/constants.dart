class AppConstants {
  AppConstants._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );

  static const String grafanaUrl = String.fromEnvironment(
    'GRAFANA_URL',
    defaultValue: 'http://localhost:3000/d/streampulse',
  );

  static const String appName = 'StreamPulse';

  // Storage keys
  static const String accessTokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String themePreferenceKey = 'theme_preference';

  // Timeouts
  static const Duration connectionTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 15);
  static const Duration splashDuration = Duration(seconds: 2);
  static const Duration snackBarDuration = Duration(seconds: 3);
  static const Duration debounceDelay = Duration(milliseconds: 300);

  // Pagination
  static const int defaultPageSize = 20;

  // Audio
  static const double defaultVolume = 0.8;
  static const List<String> supportedFormats = ['mp3', 'aac', 'ogg', 'flac'];
}
