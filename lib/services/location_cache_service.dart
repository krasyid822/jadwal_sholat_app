import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter/foundation.dart';

class LocationCacheService {
  static const String _cacheKeyPosition = 'cached_position';
  static const String _cacheKeyPlacemark = 'cached_placemark';
  static const String _cacheKeyTimestamp = 'cached_timestamp';
  static const String _cacheKeyAccuracy = 'cached_accuracy';

  /// Cache lokasi dan placemark
  static Future<void> cacheLocation({
    required Position position,
    required Placemark placemark,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      // Cache position
      final positionData = {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'altitude': position.altitude,
        'accuracy': position.accuracy,
        'heading': position.heading,
        'speed': position.speed,
        'speedAccuracy': position.speedAccuracy,
        'timestamp': position.timestamp.millisecondsSinceEpoch,
      };

      // Cache placemark
      final placemarkData = {
        'name': placemark.name,
        'street': placemark.street,
        'isoCountryCode': placemark.isoCountryCode,
        'country': placemark.country,
        'postalCode': placemark.postalCode,
        'administrativeArea': placemark.administrativeArea,
        'subAdministrativeArea': placemark.subAdministrativeArea,
        'locality': placemark.locality,
        'subLocality': placemark.subLocality,
        'thoroughfare': placemark.thoroughfare,
        'subThoroughfare': placemark.subThoroughfare,
      };

      await prefs.setString(_cacheKeyPosition, jsonEncode(positionData));
      await prefs.setString(_cacheKeyPlacemark, jsonEncode(placemarkData));
      await prefs.setInt(_cacheKeyTimestamp, timestamp);
      await prefs.setDouble(_cacheKeyAccuracy, position.accuracy);

      debugPrint(
        'Location cached: ${placemark.locality}, ${placemark.administrativeArea}',
      );
    } catch (e) {
      debugPrint('Error caching location: $e');
    }
  }

  /// Ambil lokasi yang dicache
  static Future<Map<String, dynamic>?> getCachedLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final positionJson = prefs.getString(_cacheKeyPosition);
      final placemarkJson = prefs.getString(_cacheKeyPlacemark);
      final timestamp = prefs.getInt(_cacheKeyTimestamp);
      final accuracy = prefs.getDouble(_cacheKeyAccuracy);

      if (positionJson == null || placemarkJson == null || timestamp == null) {
        return null;
      }

      // Parse position data
      final positionData = jsonDecode(positionJson) as Map<String, dynamic>;
      final position = Position(
        latitude: positionData['latitude']?.toDouble() ?? 0.0,
        longitude: positionData['longitude']?.toDouble() ?? 0.0,
        timestamp: positionData['timestamp'] != null
            ? DateTime.fromMillisecondsSinceEpoch(positionData['timestamp'])
            : DateTime.now(),
        accuracy: positionData['accuracy']?.toDouble() ?? 0.0,
        altitude: positionData['altitude']?.toDouble() ?? 0.0,
        altitudeAccuracy: 0.0,
        heading: positionData['heading']?.toDouble() ?? 0.0,
        headingAccuracy: 0.0,
        speed: positionData['speed']?.toDouble() ?? 0.0,
        speedAccuracy: positionData['speedAccuracy']?.toDouble() ?? 0.0,
      );

      // Parse placemark data
      final placemarkData = jsonDecode(placemarkJson) as Map<String, dynamic>;
      final placemark = Placemark(
        name: placemarkData['name'],
        street: placemarkData['street'],
        isoCountryCode: placemarkData['isoCountryCode'],
        country: placemarkData['country'],
        postalCode: placemarkData['postalCode'],
        administrativeArea: placemarkData['administrativeArea'],
        subAdministrativeArea: placemarkData['subAdministrativeArea'],
        locality: placemarkData['locality'],
        subLocality: placemarkData['subLocality'],
        thoroughfare: placemarkData['thoroughfare'],
        subThoroughfare: placemarkData['subThoroughfare'],
      );

      final cacheAge = DateTime.now().millisecondsSinceEpoch - timestamp;
      final cacheAgeHours = cacheAge / (1000 * 60 * 60);

      return {
        'position': position,
        'placemark': placemark,
        'timestamp': DateTime.fromMillisecondsSinceEpoch(timestamp),
        'accuracy': accuracy ?? 0.0,
        'cache_age_hours': cacheAgeHours,
      };
    } catch (e) {
      debugPrint('Error getting cached location: $e');
      return null;
    }
  }

  /// Cek apakah cache masih valid (kurang dari maxAgeHours jam)
  static Future<bool> isCacheValid({double maxAgeHours = 24.0}) async {
    try {
      final cached = await getCachedLocation();
      if (cached == null) return false;

      final cacheAgeHours = cached['cache_age_hours'] as double;
      return cacheAgeHours < maxAgeHours;
    } catch (e) {
      debugPrint('Error checking cache validity: $e');
      return false;
    }
  }

  /// Hapus cache lokasi
  static Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKeyPosition);
      await prefs.remove(_cacheKeyPlacemark);
      await prefs.remove(_cacheKeyTimestamp);
      await prefs.remove(_cacheKeyAccuracy);
      debugPrint('Location cache cleared');
    } catch (e) {
      debugPrint('Error clearing location cache: $e');
    }
  }

  /// Ambil ringkasan cache untuk debugging
  static Future<String> getCacheSummary() async {
    try {
      final cached = await getCachedLocation();
      if (cached == null) {
        return 'No cached location';
      }

      final position = cached['position'] as Position;
      final placemark = cached['placemark'] as Placemark;
      final timestamp = cached['timestamp'] as DateTime;
      final accuracy = cached['accuracy'] as double;
      final cacheAgeHours = cached['cache_age_hours'] as double;

      return '''
Cached Location Summary:
- Location: ${placemark.locality}, ${placemark.administrativeArea}
- Coordinates: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}
- Accuracy: ${accuracy.toStringAsFixed(1)}m
- Cached: ${timestamp.toString()}
- Age: ${cacheAgeHours.toStringAsFixed(1)} hours
''';
    } catch (e) {
      return 'Error getting cache summary: $e';
    }
  }

  /// Force refresh cache dengan lokasi baru
  static Future<void> forceRefreshCache() async {
    try {
      await clearCache();

      // Ambil lokasi baru
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        await cacheLocation(position: position, placemark: placemarks.first);
        debugPrint('Cache force refreshed successfully');
      }
    } catch (e) {
      debugPrint('Error force refreshing cache: $e');
      rethrow;
    }
  }
}
