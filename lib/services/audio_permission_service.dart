import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class AudioPermissionService {
  /// Request audio permissions required for auto-play
  static Future<bool> requestAudioPermissions() async {
    try {
      // Request microphone permission (required for audio sessions on some devices)
      final micPermission = await Permission.microphone.request();

      // Request notification permission (required for background audio)
      final notificationPermission = await Permission.notification.request();

      // Check if permissions are granted
      final notificationGranted =
          notificationPermission == PermissionStatus.granted;

      debugPrint('🎧 Audio Permission Status:');
      debugPrint('  📱 Microphone: ${micPermission.name}');
      debugPrint('  🔔 Notification: ${notificationPermission.name}');

      // Return true if notification is granted (microphone is optional)
      return notificationGranted;
    } catch (e) {
      debugPrint('❌ Error requesting audio permissions: $e');
      return false;
    }
  }

  /// Check current audio permission status
  static Future<Map<String, bool>> checkAudioPermissions() async {
    try {
      final micStatus = await Permission.microphone.status;
      final notificationStatus = await Permission.notification.status;

      return {
        'microphone': micStatus == PermissionStatus.granted,
        'notification': notificationStatus == PermissionStatus.granted,
        'canPlayAudio': notificationStatus == PermissionStatus.granted,
      };
    } catch (e) {
      debugPrint('❌ Error checking audio permissions: $e');
      return {
        'microphone': false,
        'notification': false,
        'canPlayAudio': false,
      };
    }
  }

  /// Open app settings for manual permission grant
  static Future<bool> openSettings() async {
    try {
      return await openAppSettings();
    } catch (e) {
      debugPrint('❌ Error opening settings: $e');
      return false;
    }
  }
}
