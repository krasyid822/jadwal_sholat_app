import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;

/// Configuration class untuk environment variables
class EnvironmentConfig {
  // Flutter & Android SDK Paths
    static String get flutterSdkPath {
        final v = _getEnv('FLUTTER_ROOT') ?? _getEnv('FLUTTER_SDK');
        return v ?? r'D:\flutter\flutter';
    }

    static String get androidSdkPath {
        final v = _getEnv('ANDROID_SDK_ROOT') ?? _getEnv('ANDROID_HOME');
        return v ?? r'D:\flutter\android-sdk';
    }

  // Java Configuration
    static String get javaHome => _getEnv('JAVA_HOME') ?? r'D:\Program Files\Java\jdk-24';

  // Gradle Configuration
    static String get gradleHome {
        final v = _getEnv('GRADLE_HOME') ?? _getEnv('GRADLE_USER_HOME');
        final userProfile = _getEnv('USERPROFILE');
        return v ?? (userProfile != null ? '$userProfile/.gradle' : r'C:\Users\%USERNAME%\\.gradle');
    }

  // Build Configuration
    static String get buildMode => _getEnv('FLUTTER_BUILD_MODE') ?? 'debug';

    static String get buildVariant => _getEnv('BUILD_VARIANT') ?? 'debug';

  // Performance Configuration
    static String get gradleJvmArgs =>
            _getEnv('GRADLE_OPTS') ??
            '-Xmx8G -XX:MaxMetaspaceSize=4G -XX:ReservedCodeCacheSize=512m -XX:+HeapDumpOnOutOfMemoryError';

  // Network Configuration
    static String get httpProxyHost => _getEnv('HTTP_PROXY_HOST') ?? '';
    static String get httpProxyPort => _getEnv('HTTP_PROXY_PORT') ?? '';
    static String get httpsProxyHost => _getEnv('HTTPS_PROXY_HOST') ?? '';
    static String get httpsProxyPort => _getEnv('HTTPS_PROXY_PORT') ?? '';

  // Development Configuration
    static bool get isDebugMode =>
            kDebugMode ||
            (_getEnv('DEBUG') == 'true') ||
            (_getEnv('FLUTTER_BUILD_MODE') == 'debug');

    static String get logLevel => _getEnv('LOG_LEVEL') ?? 'info';

  // Signing Configuration (untuk release builds)
    static String get keystorePath => _getEnv('KEYSTORE_PATH') ?? '';

    static String get keystorePassword => _getEnv('KEYSTORE_PASSWORD') ?? '';

    static String get keyAlias => _getEnv('KEY_ALIAS') ?? '';

    static String get keyPassword => _getEnv('KEY_PASSWORD') ?? '';

  // API Configuration
    static String get apiBaseUrl => _getEnv('API_BASE_URL') ?? 'https://api.aladhan.com/v1';

  // App Configuration
    static String get appName => _getEnv('APP_NAME') ?? 'Jadwal Sholat App';

    static String get appVersion => _getEnv('APP_VERSION') ?? '1.0.0';

  // Helper method untuk print semua environment variables
  static void printEnvironmentInfo() {
    developer.log('=== Environment Configuration ===');
    developer.log('Flutter SDK: $flutterSdkPath');
    developer.log('Android SDK: $androidSdkPath');
    developer.log('Java Home: $javaHome');
    developer.log('Gradle Home: $gradleHome');
    developer.log('Build Mode: $buildMode');
    developer.log('Debug Mode: $isDebugMode');
    developer.log('API Base URL: $apiBaseUrl');
    developer.log('================================');
  }

  // Validate environment setup
  static List<String> validateEnvironment() {
    // Directory checks are not supported on web; skip when running in browser.
    if (kIsWeb) return [];

    final issues = <String>[];

    try {
      if (!Directory(flutterSdkPath).existsSync()) {
        issues.add('Flutter SDK path not found: $flutterSdkPath');
      }
    } catch (_) {}

    try {
      if (!Directory(androidSdkPath).existsSync()) {
        issues.add('Android SDK path not found: $androidSdkPath');
      }
    } catch (_) {}

    try {
      if (!Directory(javaHome).existsSync()) {
        issues.add('Java Home path not found: $javaHome');
      }
    } catch (_) {}

    return issues;
  }

    // Helper to safely read environment variables; returns null on web or if unsupported.
    static String? _getEnv(String key) {
        if (kIsWeb) return null;
        try {
            return Platform.environment[key];
        } catch (e) {
            return null;
        }
    }
}
