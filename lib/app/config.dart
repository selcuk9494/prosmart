import 'package:flutter/foundation.dart';

class AppConfig {
  static const _apiBaseUrlEnv = String.fromEnvironment('API_BASE_URL', defaultValue: '');
  static const forceDemo = bool.fromEnvironment('FORCE_DEMO', defaultValue: false);

  static String get apiBaseUrl {
    final v = _apiBaseUrlEnv.trim();
    if (v.isNotEmpty) return v;
    if (kReleaseMode && !kIsWeb) return 'https://prosmart-ten.vercel.app';
    return '';
  }

  static bool get hasApi => !forceDemo && apiBaseUrl.trim().isNotEmpty;
}
