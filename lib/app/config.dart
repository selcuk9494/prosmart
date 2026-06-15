import 'package:flutter/foundation.dart';

class AppConfig {
  static const _apiBaseUrlEnv = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );
  static const _omniApiBaseUrlEnv = String.fromEnvironment(
    'OMNI_API_BASE_URL',
    defaultValue: '',
  );
  static const forceDemo = bool.fromEnvironment(
    'FORCE_DEMO',
    defaultValue: false,
  );

  static String get apiBaseUrl {
    final v = _apiBaseUrlEnv.trim();
    if (v.isNotEmpty) return v;
    if (kIsWeb) return '';
    if (kReleaseMode) return 'https://prosmarterp.vercel.app';
    return '';
  }

  static bool get hasApi =>
      !forceDemo && (apiBaseUrl.trim().isNotEmpty || (kIsWeb && kReleaseMode));

  static String get omniApiBaseUrl => _omniApiBaseUrlEnv.trim();

  static bool get hasOmniApi => !forceDemo && omniApiBaseUrl.isNotEmpty;
}
