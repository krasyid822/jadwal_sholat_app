import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ErrorLogger {
  static final ErrorLogger _instance = ErrorLogger._internal();
  static ErrorLogger get instance => _instance;

  ErrorLogger._internal();

  Future<void> initialize() async {
    debugPrint('ErrorLogger initialized');
  }

  Future<void> logError({
    required String message,
    required dynamic error,
    StackTrace? stackTrace,
    String? context,
  }) async {
    final timestamp = DateTime.now().toIso8601String();
    final errorMessage =
        '''
[$timestamp] ERROR in $context:
Message: $message
Error: $error
StackTrace: ${stackTrace ?? 'No stack trace'}
''';

    debugPrint(errorMessage);
    developer.log(
      errorMessage,
      name: 'ErrorLogger',
      error: error,
      stackTrace: stackTrace,
    );

    // Optionally save to SharedPreferences for debugging
    try {
      final prefs = await SharedPreferences.getInstance();
      final errors = prefs.getStringList('app_errors') ?? [];
      errors.add(errorMessage);

      // Keep only last 50 errors
      if (errors.length > 50) {
        errors.removeRange(0, errors.length - 50);
      }

      await prefs.setStringList('app_errors', errors);
    } catch (e) {
      debugPrint('Failed to save error log: $e');
    }
  }

  Future<void> logPermissionError({
    required String permission,
    required String status,
    String? context,
  }) async {
    final message = 'Permission $permission has status: $status';
    await logError(
      message: message,
      error: 'PermissionError',
      context: context ?? 'permission_check',
    );
  }

  Future<List<String>> getStoredErrors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList('app_errors') ?? [];
    } catch (e) {
      debugPrint('Failed to get stored errors: $e');
      return [];
    }
  }

  Future<void> clearStoredErrors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('app_errors');
      debugPrint('Stored errors cleared');
    } catch (e) {
      debugPrint('Failed to clear stored errors: $e');
    }
  }
}
