import 'package:flutter/foundation.dart';

class AppConfig {
  static String get apiBaseUrl {
    const configuredUrl = String.fromEnvironment('FOODSCAN_API_BASE_URL');
    if (configuredUrl.isNotEmpty) return configuredUrl;
    if (kIsWeb) return 'http://127.0.0.1:8000';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }
}
