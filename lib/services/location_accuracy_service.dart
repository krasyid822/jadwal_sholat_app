import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'error_logger.dart';
import 'location_permission_service.dart';

/// Service untuk meningkatkan akurasi lokasi menggunakan berbagai metode
class LocationAccuracyService {
  static const String _lastPositionKey = 'last_accurate_position';
  static const String _lastTimestampKey = 'last_position_timestamp';
  static const Duration _cacheValidDuration = Duration(hours: 1);

  /// Mendapatkan posisi dengan akurasi tinggi
  static Future<Position> getAccuratePosition({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      // Check permission first before attempting to get location
      final hasPermission =
          await LocationPermissionService.checkAndRequestPermission();
      if (!hasPermission) {
        throw Exception('Location permission denied or unavailable');
      }

      debugPrint('🎯 Getting accurate position with permission granted...');

      // Coba ambil posisi dengan akurasi terbaik
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 1,
        ),
      ).timeout(timeout);

      // Validasi akurasi posisi
      if (position.accuracy > 20) {
        debugPrint(
          'Position accuracy is low: ${position.accuracy}m. Trying to improve...',
        );

        // Coba sekali lagi dengan timeout lebih lama
        final betterPosition = await _getImprovedPosition(position);
        await _storePosition(betterPosition);
        return betterPosition;
      }

      await _storePosition(position);
      return position;
    } catch (e, stackTrace) {
      await ErrorLogger.instance.logError(
        message: 'Failed to get accurate position',
        error: e,
        stackTrace: stackTrace,
        context: 'LocationAccuracyService.getAccuratePosition',
      );

      // Jika gagal mendapatkan posisi baru, gunakan yang tersimpan
      final storedPosition = await _getStoredPosition();
      if (storedPosition != null) {
        return storedPosition;
      }

      // Jika tidak ada posisi tersimpan, lempar error
      rethrow;
    }
  }

  /// Mencoba meningkatkan akurasi posisi
  static Future<Position> _getImprovedPosition(Position initialPosition) async {
    try {
      // Tunggu sebentar dan coba lagi
      await Future.delayed(const Duration(seconds: 2));

      final improvedPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
        ),
      ).timeout(const Duration(seconds: 20));

      // Gunakan posisi yang lebih akurat
      if (improvedPosition.accuracy < initialPosition.accuracy) {
        debugPrint(
          'Improved accuracy from ${initialPosition.accuracy}m to ${improvedPosition.accuracy}m',
        );
        return improvedPosition;
      }

      return initialPosition;
    } catch (e) {
      debugPrint('Failed to improve position accuracy: $e');
      return initialPosition;
    }
  }

  /// Menyimpan posisi terakhir
  static Future<void> _storePosition(Position position) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final positionData = {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'altitude': position.altitude,
        'heading': position.heading,
        'speed': position.speed,
        'timestamp': position.timestamp.millisecondsSinceEpoch,
      };

      await prefs.setString(_lastPositionKey, jsonEncode(positionData));
      await prefs.setInt(
        _lastTimestampKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      debugPrint('Failed to store position: $e');
    }
  }

  /// Mengambil posisi tersimpan
  static Future<Position?> _getStoredPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final positionJson = prefs.getString(_lastPositionKey);
      final timestamp = prefs.getInt(_lastTimestampKey);

      if (positionJson == null || timestamp == null) {
        return null;
      }

      // Periksa apakah cache masih valid
      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      if (DateTime.now().difference(cacheTime) > _cacheValidDuration) {
        debugPrint('Stored position is too old, discarding');
        return null;
      }

      final positionData = jsonDecode(positionJson) as Map<String, dynamic>;

      return Position(
        latitude: positionData['latitude'] as double,
        longitude: positionData['longitude'] as double,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          positionData['timestamp'] as int,
        ),
        accuracy: positionData['accuracy'] as double,
        altitude: positionData['altitude'] as double,
        altitudeAccuracy: 0.0,
        heading: positionData['heading'] as double,
        headingAccuracy: 0.0,
        speed: positionData['speed'] as double,
        speedAccuracy: 0.0,
      );
    } catch (e) {
      debugPrint('Failed to get stored position: $e');
      return null;
    }
  }

  /// Validasi koordinat Indonesia
  static bool isValidIndonesianCoordinate(Position position) {
    // Indonesia coordinate bounds (approximately)
    const double minLat = -11.0; // Southern Indonesia
    const double maxLat = 6.0; // Northern Indonesia
    const double minLng = 95.0; // Western Indonesia
    const double maxLng = 141.0; // Eastern Indonesia

    return position.latitude >= minLat &&
        position.latitude <= maxLat &&
        position.longitude >= minLng &&
        position.longitude <= maxLng;
  }

  /// Mendapatkan elevasi (placeholder implementation)
  static Future<double> getElevation(Position position) async {
    try {
      // Untuk implementasi sederhana, return altitude dari GPS
      // Dalam implementasi nyata, Anda bisa menggunakan Google Elevation API
      return position.altitude;
    } catch (e) {
      debugPrint('Failed to get elevation: $e');
      return 0.0; // Default sea level
    }
  }

  /// Validasi akurasi lokasi dengan Google Maps API (opsional)
  static Future<bool> validateLocationAccuracy(Position position) async {
    try {
      // Ini adalah implementasi sederhana untuk validasi
      // Dalam implementasi nyata, Anda bisa menggunakan Google Maps API
      // untuk memverifikasi lokasi

      const double minAccuracy = 50.0; // meter
      return position.accuracy <= minAccuracy;
    } catch (e) {
      debugPrint('Failed to validate location accuracy: $e');
      return true; // Anggap valid jika tidak bisa memvalidasi
    }
  }

  /// Mendapatkan estimasi akurasi berdasarkan metode
  static String getAccuracyEstimate(double accuracy) {
    if (accuracy <= 5) {
      return 'Sangat Akurat (±${accuracy.toStringAsFixed(1)}m)';
    } else if (accuracy <= 10) {
      return 'Akurat (±${accuracy.toStringAsFixed(1)}m)';
    } else if (accuracy <= 20) {
      return 'Cukup Akurat (±${accuracy.toStringAsFixed(1)}m)';
    } else if (accuracy <= 50) {
      return 'Kurang Akurat (±${accuracy.toStringAsFixed(1)}m)';
    } else {
      return 'Tidak Akurat (±${accuracy.toStringAsFixed(1)}m)';
    }
  }

  /// Membersihkan cache lokasi
  static Future<void> clearLocationCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastPositionKey);
      await prefs.remove(_lastTimestampKey);
      debugPrint('Location cache cleared');
    } catch (e) {
      debugPrint('Failed to clear location cache: $e');
    }
  }

  /// Mendapatkan informasi cache lokasi
  static Future<Map<String, dynamic>> getCacheInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_lastTimestampKey);
      final positionJson = prefs.getString(_lastPositionKey);

      if (timestamp == null || positionJson == null) {
        return {'hasCache': false, 'cacheAge': null, 'isValid': false};
      }

      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final cacheAge = DateTime.now().difference(cacheTime);
      final isValid = cacheAge <= _cacheValidDuration;

      return {
        'hasCache': true,
        'cacheAge': cacheAge.inMinutes,
        'isValid': isValid,
        'cacheTime': cacheTime.toIso8601String(),
      };
    } catch (e) {
      return {
        'hasCache': false,
        'cacheAge': null,
        'isValid': false,
        'error': e.toString(),
      };
    }
  }
}
