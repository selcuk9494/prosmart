class AppConfig {
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');
  static const forceDemo = bool.fromEnvironment('FORCE_DEMO', defaultValue: false);

  static bool get hasApi => !forceDemo && apiBaseUrl.trim().isNotEmpty;
}
