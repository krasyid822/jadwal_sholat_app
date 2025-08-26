import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'error_logger.dart';

/// Service untuk menangani elevasi/ketinggian dengan database wilayah Indonesia
class ElevationService {
  static const String _elevationCacheKey = 'elevation_cache';
  static const String _lastElevationKey = 'last_elevation';
  static const Duration _cacheValidDuration = Duration(days: 7);

  // Database elevasi kota-kota besar Indonesia (dalam meter)
  static const Map<String, double> _indonesianCityElevations = {
    // Pulau Jawa
    'jakarta': 8,
    'bandung': 768,
    'surabaya': 6,
    'yogyakarta': 113,
    'semarang': 3,
    'malang': 444,
    'bogor': 190,
    'depok': 50,
    'tangerang': 12,
    'bekasi': 19,
    'cirebon': 5,
    'solo': 92,
    'purwokerto': 83,
    'magelang': 380,
    'tegal': 9,
    'pekalongan': 1,
    'salatiga': 450,
    'sukabumi': 584,
    'tasikmalaya': 351,
    'garut': 717,

    // Pulau Sumatera
    'medan': 25,
    'palembang': 8,
    'pekanbaru': 10,
    'batam': 27,
    'bandar lampung': 96,
    'padang': 7,
    'jambi': 35,
    'bengkulu': 10,
    'dumai': 41,
    'binjai': 36,
    'tanjungpinang': 178,
    'bukittinggi': 930,
    'payakumbuh': 501,
    'lubuklinggau': 67,
    'prabumulih': 64,
    'pangkalpinang': 50,
    'tanjungbalai': 1,
    'sibolga': 3,
    'tebing tinggi': 31,
    'lhokseumawe': 5,

    // Pulau Kalimantan
    'pontianak': 1,
    'banjarmasin': 8,
    'balikpapan': 4,
    'samarinda': 10,
    'palangkaraya': 25,
    'tarakan': 5,
    'singkawang': 28,
    'bontang': 5,
    'banjar baru': 45,

    // Pulau Sulawesi
    'makassar': 8,
    'manado': 5,
    'palu': 89,
    'kendari': 50,
    'gorontalo': 23,
    'parepare': 5,
    'palopo': 87,
    'bitung': 100,
    'tomohon': 700,
    'kotamobagu': 116,

    // Pulau Papua
    'jayapura': 5,
    'sorong': 83,
    'merauke': 5,
    'nabire': 1,
    'timika': 74,
    'manokwari': 5,
    'wamena': 1550,

    // Nusa Tenggara
    'denpasar': 4,
    'mataram': 75,
    'kupang': 178,
    'singaraja': 100,
    'ende': 430,
    'maumere': 40,
    'labuan bajo': 200,
    'bima': 142,

    // Maluku
    'ambon': 56,
    'ternate': 47,
    'tual': 12,
    'namlea': 10,
    'masohi': 20,
  };

  /// Mendapatkan elevasi dengan multiple fallback methods
  static Future<double> getAccurateElevation(
    Position position, {
    String? cityName,
  }) async {
    try {
      // Prefer sources in order of measured accuracy:
      // 1) GPS altitude if reported and horizontal accuracy is good
      // 2) Cached elevation
      // 3) Estimated elevation by coordinates
      // 4) City database as last resort

      // Read optional threshold from SharedPreferences. If not set, accept GPS altitude when present.
      final prefs = await SharedPreferences.getInstance();
      final double? accuracyThresholdMeters = prefs.getDouble(
        'elevation_accuracy_threshold_m',
      );

      // 1) GPS altitude if altitude value is in expected range
      if (position.altitude > -1000 && position.altitude < 9000) {
        final acc = position.accuracy; // horizontal accuracy in meters
        if (accuracyThresholdMeters == null) {
          // No configured threshold: accept GPS altitude directly
          await _cacheElevation(
            position.latitude,
            position.longitude,
            position.altitude,
          );
          debugPrint(
            'Using GPS altitude (no threshold configured, accuracy ${acc}m): ${position.altitude}m',
          );
          return position.altitude;
        } else {
          if (acc <= accuracyThresholdMeters) {
            await _cacheElevation(
              position.latitude,
              position.longitude,
              position.altitude,
            );
            debugPrint(
              'Using GPS altitude (accuracy ${acc}m <= threshold ${accuracyThresholdMeters}m): ${position.altitude}m',
            );
            return position.altitude;
          } else {
            debugPrint(
              'GPS altitude ignored due to poor accuracy ($acc m) vs threshold ${accuracyThresholdMeters}m: ${position.altitude}m',
            );
          }
        }
      }

      // 2) Cached elevation
      final cachedElevation = await _getCachedElevation(
        position.latitude,
        position.longitude,
      );
      if (cachedElevation != null) {
        debugPrint('Using cached elevation: ${cachedElevation}m');
        return cachedElevation;
      }

      // 3) Estimation based on region
      final estimatedElevation = _estimateElevationByRegion(
        position.latitude,
        position.longitude,
      );
      if (estimatedElevation >= 0) {
        await _cacheElevation(
          position.latitude,
          position.longitude,
          estimatedElevation,
        );
        debugPrint('Using estimated elevation: ${estimatedElevation}m');
        return estimatedElevation;
      }

      // 4) City database as last resort
      if (cityName != null) {
        final cityElevation = _getCityElevation(cityName);
        if (cityElevation != null) {
          await _cacheElevation(
            position.latitude,
            position.longitude,
            cityElevation,
          );
          debugPrint(
            'Using city database elevation for $cityName: ${cityElevation}m',
          );
          return cityElevation;
        }
      }

      // If all else fails, fallback to last known or zero
      final last = await _getLastKnownElevation();
      debugPrint('All elevation methods failed, using last known: ${last}m');
      return last;
    } catch (e, stackTrace) {
      await ErrorLogger.instance.logError(
        message: 'Failed to get accurate elevation',
        error: e,
        stackTrace: stackTrace,
        context: 'ElevationService.getAccurateElevation',
      );

      // Fallback: gunakan elevasi terakhir yang tersimpan atau 0
      final lastElevation = await _getLastKnownElevation();
      debugPrint('Using fallback elevation: ${lastElevation}m');
      return lastElevation;
    }
  }

  /// Mendapatkan elevasi kota dari database
  static double? _getCityElevation(String cityName) {
    final normalizedName = cityName.toLowerCase().trim();

    // Coba exact match terlebih dahulu
    if (_indonesianCityElevations.containsKey(normalizedName)) {
      return _indonesianCityElevations[normalizedName];
    }

    // Coba partial match untuk kota dengan nama lengkap
    for (final entry in _indonesianCityElevations.entries) {
      if (normalizedName.contains(entry.key) ||
          entry.key.contains(normalizedName)) {
        return entry.value;
      }
    }

    return null;
  }

  /// Estimasi elevasi berdasarkan wilayah geografis Indonesia
  static double _estimateElevationByRegion(double latitude, double longitude) {
    // Pegunungan tinggi Indonesia
    if (_isInMountainousRegion(latitude, longitude)) {
      return 500.0; // Default untuk daerah pegunungan
    }

    // Dataran tinggi
    if (_isInHighlandRegion(latitude, longitude)) {
      return 200.0; // Default untuk dataran tinggi
    }

    // Wilayah pantai dan dataran rendah
    if (_isInCoastalRegion(latitude, longitude)) {
      return 10.0; // Default untuk daerah pantai
    }

    // Default untuk daerah lainnya
    return 50.0;
  }

  /// Public helper to estimate elevation for external callers when GPS altitude is unavailable
  static double estimateElevationByCoordinates(
    double latitude,
    double longitude,
  ) {
    return _estimateElevationByRegion(latitude, longitude);
  }

  /// Cek apakah koordinat berada di wilayah pegunungan
  static bool _isInMountainousRegion(double lat, double lng) {
    // Pegunungan Jawa Barat (Bandung, Bogor, Sukabumi)
    if (lat >= -7.0 && lat <= -6.5 && lng >= 106.5 && lng <= 108.0) {
      return true;
    }

    // Pegunungan Jawa Tengah (Dieng, Merapi)
    if (lat >= -7.8 && lat <= -7.0 && lng >= 109.5 && lng <= 111.0) {
      return true;
    }

    // Pegunungan Sumatera Barat (Bukittinggi, Padang Panjang)
    if (lat >= -1.0 && lat <= 0.5 && lng >= 100.0 && lng <= 101.0) {
      return true;
    }

    // Pegunungan Papua (Wamena, Jayawijaya)
    if (lat >= -4.5 && lat <= -3.5 && lng >= 138.5 && lng <= 140.0) {
      return true;
    }

    return false;
  }

  /// Cek apakah koordinat berada di dataran tinggi
  static bool _isInHighlandRegion(double lat, double lng) {
    // Yogyakarta dan sekitarnya
    if (lat >= -8.0 && lat <= -7.5 && lng >= 110.0 && lng <= 110.8) {
      return true;
    }

    // Malang dan sekitarnya
    if (lat >= -8.2 && lat <= -7.8 && lng >= 112.5 && lng <= 113.0) {
      return true;
    }

    return false;
  }

  /// Cek apakah koordinat berada di wilayah pantai
  static bool _isInCoastalRegion(double lat, double lng) {
    // Implementasi sederhana: jika dekat dengan batas pantai Indonesia
    // Jakarta dan sekitarnya
    if (lat >= -6.5 && lat <= -5.8 && lng >= 106.5 && lng <= 107.2) {
      return true;
    }

    // Surabaya dan sekitarnya
    if (lat >= -7.5 && lat <= -7.0 && lng >= 112.5 && lng <= 113.0) {
      return true;
    }

    return false;
  }

  /// Cache elevasi berdasarkan koordinat
  static Future<void> _cacheElevation(
    double latitude,
    double longitude,
    double elevation,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey =
          '${latitude.toStringAsFixed(3)}_${longitude.toStringAsFixed(3)}';

      final cacheData = {
        'elevation': elevation,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'latitude': latitude,
        'longitude': longitude,
      };

      await prefs.setString(
        '${_elevationCacheKey}_$cacheKey',
        jsonEncode(cacheData),
      );
      await prefs.setDouble(_lastElevationKey, elevation);
    } catch (e) {
      debugPrint('Failed to cache elevation: $e');
    }
  }

  /// Ambil elevasi dari cache
  static Future<double?> _getCachedElevation(
    double latitude,
    double longitude,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey =
          '${latitude.toStringAsFixed(3)}_${longitude.toStringAsFixed(3)}';
      final cacheJson = prefs.getString('${_elevationCacheKey}_$cacheKey');

      if (cacheJson == null) return null;

      final cacheData = jsonDecode(cacheJson) as Map<String, dynamic>;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
        cacheData['timestamp'] as int,
      );

      // Cek apakah cache masih valid
      if (DateTime.now().difference(timestamp) > _cacheValidDuration) {
        return null;
      }

      return cacheData['elevation'] as double;
    } catch (e) {
      debugPrint('Failed to get cached elevation: $e');
      return null;
    }
  }

  /// Ambil elevasi terakhir yang diketahui
  static Future<double> _getLastKnownElevation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getDouble(_lastElevationKey) ?? 0.0;
    } catch (e) {
      debugPrint('Failed to get last known elevation: $e');
      return 0.0;
    }
  }

  /// Validasi elevasi apakah masuk akal untuk Indonesia
  static bool isValidElevation(double elevation) {
    // Indonesia: dari permukaan laut sampai Puncak Jaya (4884m)
    return elevation >= 0 && elevation <= 5000;
  }

  /// Clear cache elevasi
  static Future<void> clearElevationCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where(
        (key) => key.startsWith(_elevationCacheKey),
      );

      for (final key in keys) {
        await prefs.remove(key);
      }

      debugPrint('Elevation cache cleared');
    } catch (e) {
      debugPrint('Failed to clear elevation cache: $e');
    }
  }

  /// Mendapatkan info elevasi yang readable
  static String getElevationInfo(double elevation) {
    if (elevation <= 0) {
      return 'Permukaan Laut (0m)';
    } else if (elevation <= 100) {
      return 'Dataran Rendah (${elevation.toStringAsFixed(0)}m)';
    } else if (elevation <= 500) {
      return 'Dataran Tinggi (${elevation.toStringAsFixed(0)}m)';
    } else if (elevation <= 1500) {
      return 'Pegunungan (${elevation.toStringAsFixed(0)}m)';
    } else {
      return 'Pegunungan Tinggi (${elevation.toStringAsFixed(0)}m)';
    }
  }
}
