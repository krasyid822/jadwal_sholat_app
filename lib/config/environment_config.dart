import 'dart:io';
import 'dart:developer' as developer;

/// Configuration class untuk environment variables
class EnvironmentConfig {
  // Flutter & Android SDK Paths
  static String get flutterSdkPath =>
      Platform.environment['FLUTTER_ROOT'] ??
      Platform.environment['FLUTTER_SDK'] ??
      r'D:\flutter\flutter';

  static String get androidSdkPath =>
      Platform.environment['ANDROID_SDK_ROOT'] ??
      Platform.environment['ANDROID_HOME'] ??
      r'D:\flutter\android-sdk';

  // Java Configuration
  static String get javaHome =>
      Platform.environment['JAVA_HOME'] ?? r'D:\Program Files\Java\jdk-24';

  // Gradle Configuration
  static String get gradleHome =>
      Platform.environment['GRADLE_HOME'] ??
      Platform.environment['GRADLE_USER_HOME'] ??
      '${Platform.environment['USERPROFILE']}/.gradle';

  // Build Configuration
  static String get buildMode =>
      Platform.environment['FLUTTER_BUILD_MODE'] ?? 'debug';

  static String get buildVariant =>
      Platform.environment['BUILD_VARIANT'] ?? 'debug';

  // Performance Configuration
  static String get gradleJvmArgs =>
      Platform.environment['GRADLE_OPTS'] ??
      '-Xmx8G -XX:MaxMetaspaceSize=4G -XX:ReservedCodeCacheSize=512m -XX:+HeapDumpOnOutOfMemoryError';

  // Network Configuration
  static String get httpProxyHost =>
      Platform.environment['HTTP_PROXY_HOST'] ?? '';
  static String get httpProxyPort =>
      Platform.environment['HTTP_PROXY_PORT'] ?? '';
  static String get httpsProxyHost =>
      Platform.environment['HTTPS_PROXY_HOST'] ?? '';
  static String get httpsProxyPort =>
      Platform.environment['HTTPS_PROXY_PORT'] ?? '';

  // Development Configuration
  static bool get isDebugMode =>
      Platform.environment['DEBUG'] == 'true' ||
      Platform.environment['FLUTTER_BUILD_MODE'] == 'debug';

  static String get logLevel => Platform.environment['LOG_LEVEL'] ?? 'info';

  // Signing Configuration (untuk release builds)
  static String get keystorePath => Platform.environment['KEYSTORE_PATH'] ?? '';

  static String get keystorePassword =>
      Platform.environment['KEYSTORE_PASSWORD'] ?? '';

  static String get keyAlias => Platform.environment['KEY_ALIAS'] ?? '';

  static String get keyPassword => Platform.environment['KEY_PASSWORD'] ?? '';

  // API Configuration
  static String get apiBaseUrl =>
      Platform.environment['API_BASE_URL'] ?? 'https://api.aladhan.com/v1';

  // App Configuration
  static String get appName =>
      Platform.environment['APP_NAME'] ?? 'Jadwal Sholat App';

  static String get appVersion =>
      Platform.environment['APP_VERSION'] ?? '1.0.0';

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
    List<String> issues = [];

    if (!Directory(flutterSdkPath).existsSync()) {
      issues.add('Flutter SDK path not found: $flutterSdkPath');
    }

    if (!Directory(androidSdkPath).existsSync()) {
      issues.add('Android SDK path not found: $androidSdkPath');
    }

    if (!Directory(javaHome).existsSync()) {
      issues.add('Java Home path not found: $javaHome');
    }

    return issues;
  }
}
