import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Service untuk menangani location permissions dengan proper error handling
class LocationPermissionService {
  /// Check dan request location permission dengan user-friendly handling
  static Future<bool> checkAndRequestPermission() async {
    try {
      debugPrint('🔍 Checking location permission...');

      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('❌ Location services are disabled');
        return false;
      }

      // Check current permission status
      LocationPermission permission = await Geolocator.checkPermission();
      debugPrint('📍 Current permission status: ${permission.name}');

      // Handle different permission states
      switch (permission) {
        case LocationPermission.always:
        case LocationPermission.whileInUse:
          debugPrint('✅ Location permission already granted');
          return true;

        case LocationPermission.denied:
          debugPrint('🔒 Permission denied, requesting permission...');
          permission = await Geolocator.requestPermission();

          if (permission == LocationPermission.whileInUse ||
              permission == LocationPermission.always) {
            debugPrint('✅ Permission granted after request');
            return true;
          } else {
            debugPrint('❌ Permission denied after request');
            return false;
          }

        case LocationPermission.deniedForever:
          debugPrint('🚫 Permission denied forever - need to open settings');
          return false;

        case LocationPermission.unableToDetermine:
          debugPrint('❓ Unable to determine permission status');
          return false;
      }
    } catch (e) {
      debugPrint('❌ Error checking location permission: $e');
      return false;
    }
  }

  /// Get current permission status without requesting
  static Future<LocationPermission> getCurrentPermissionStatus() async {
    try {
      return await Geolocator.checkPermission();
    } catch (e) {
      debugPrint('Error getting permission status: $e');
      return LocationPermission.unableToDetermine;
    }
  }

  /// Check if location services are enabled
  static Future<bool> isLocationServiceEnabled() async {
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (e) {
      debugPrint('Error checking location service: $e');
      return false;
    }
  }

  /// Open app settings for manual permission grant
  static Future<bool> openLocationSettings() async {
    try {
      return await Geolocator.openLocationSettings();
    } catch (e) {
      debugPrint('Error opening location settings: $e');
      return false;
    }
  }

  /// Open app-specific settings
  static Future<bool> openAppSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } catch (e) {
      debugPrint('Error opening app settings: $e');
      return false;
    }
  }

  /// Get permission status description for UI
  static String getPermissionDescription(LocationPermission permission) {
    switch (permission) {
      case LocationPermission.always:
        return 'Location access granted (always)';
      case LocationPermission.whileInUse:
        return 'Location access granted (while in use)';
      case LocationPermission.denied:
        return 'Location access denied';
      case LocationPermission.deniedForever:
        return 'Location access permanently denied';
      case LocationPermission.unableToDetermine:
        return 'Unable to determine location permission';
    }
  }

  /// Check if permission allows location access
  static bool isPermissionGranted(LocationPermission permission) {
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }
}
