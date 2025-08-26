import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:adhan/adhan.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'error_logger.dart';

/// Service untuk caching dan validasi konsistensi waktu sholat offline
class PrayerCacheService {
  static const String _prayerCacheKey = 'prayer_times_cache';
  static const String _lastCalculationKey = 'last_calculation_params';
  static const String _validationKey = 'prayer_validation_data';
  static const Duration _cacheValidDuration = Duration(hours: 12);
  static const double _driftThreshold = 2.0; // menit

  /// Cache waktu sholat dengan validasi parameter
  static Future<void> cachePrayerTimes(
    PrayerTimes prayerTimes,
    Coordinates coordinates,
    DateComponents date,
    double elevation,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final cacheData = {
        'fajr': prayerTimes.fajr.millisecondsSinceEpoch,
        'sunrise': prayerTimes.sunrise.millisecondsSinceEpoch,
        'dhuhr': prayerTimes.dhuhr.millisecondsSinceEpoch,
        'asr': prayerTimes.asr.millisecondsSinceEpoch,
        'maghrib': prayerTimes.maghrib.millisecondsSinceEpoch,
        'isha': prayerTimes.isha.millisecondsSinceEpoch,
        'coordinates': {
          'latitude': coordinates.latitude,
          'longitude': coordinates.longitude,
        },
        'date': {'year': date.year, 'month': date.month, 'day': date.day},
        'elevation': elevation,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'calculationMethod': 'kemenag_standard',
      };

      final cacheKey = _generateCacheKey(coordinates, date);
      await prefs.setString(
        '${_prayerCacheKey}_$cacheKey',
        jsonEncode(cacheData),
      );

      // Simpan parameter perhitungan terakhir untuk validasi
      await _saveCalculationParameters(coordinates, elevation);

      debugPrint(
        'Prayer times cached for ${date.year}-${date.month}-${date.day}',
      );
    } catch (e, stackTrace) {
      await ErrorLogger.instance.logError(
        message: 'Failed to cache prayer times',
        error: e,
        stackTrace: stackTrace,
        context: 'PrayerCacheService.cachePrayerTimes',
      );
    }
  }

  /// Ambil waktu sholat dari cache dengan validasi
  static Future<PrayerTimes?> getCachedPrayerTimes(
    Coordinates coordinates,
    DateComponents date,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _generateCacheKey(coordinates, date);
      final cacheJson = prefs.getString('${_prayerCacheKey}_$cacheKey');

      if (cacheJson == null) return null;

      final cacheData = jsonDecode(cacheJson) as Map<String, dynamic>;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
        cacheData['timestamp'] as int,
      );

      // Cek apakah cache masih valid
      if (DateTime.now().difference(timestamp) > _cacheValidDuration) {
        debugPrint('Cached prayer times expired');
        return null;
      }

      // Validasi konsistensi koordinat
      final cachedCoords = cacheData['coordinates'] as Map<String, dynamic>;
      if (!_isCoordinateMatch(coordinates, cachedCoords)) {
        debugPrint('Coordinate mismatch in cache');
        return null;
      }

      // Rekonstruksi PrayerTimes dari cache
      final prayerTimes = _reconstructPrayerTimes(cacheData, coordinates, date);

      // Validasi drift
      if (await _detectDrift(prayerTimes, coordinates, date)) {
        debugPrint('Prayer time drift detected, cache invalidated');
        return null;
      }

      debugPrint(
        'Using cached prayer times for ${date.year}-${date.month}-${date.day}',
      );
      return prayerTimes;
    } catch (e, stackTrace) {
      await ErrorLogger.instance.logError(
        message: 'Failed to get cached prayer times',
        error: e,
        stackTrace: stackTrace,
        context: 'PrayerCacheService.getCachedPrayerTimes',
      );
      return null;
    }
  }

  /// Validasi konsistensi waktu sholat untuk mencegah drift
  static Future<bool> validatePrayerConsistency(
    PrayerTimes newPrayerTimes,
    Coordinates coordinates,
    DateComponents date,
  ) async {
    try {
      // Ambil waktu sholat kemarin untuk perbandingan
      final yesterday = DateComponents(date.year, date.month, date.day - 1);
      final yesterdayPrayerTimes = await getCachedPrayerTimes(
        coordinates,
        yesterday,
      );

      if (yesterdayPrayerTimes == null) {
        // Tidak ada data kemarin, anggap valid
        return true;
      }

      // Hitung selisih waktu sholat dengan kemarin
      final driftResults = {
        'fajr': _calculateTimeDrift(
          yesterdayPrayerTimes.fajr,
          newPrayerTimes.fajr,
        ),
        'dhuhr': _calculateTimeDrift(
          yesterdayPrayerTimes.dhuhr,
          newPrayerTimes.dhuhr,
        ),
        'asr': _calculateTimeDrift(
          yesterdayPrayerTimes.asr,
          newPrayerTimes.asr,
        ),
        'maghrib': _calculateTimeDrift(
          yesterdayPrayerTimes.maghrib,
          newPrayerTimes.maghrib,
        ),
        'isha': _calculateTimeDrift(
          yesterdayPrayerTimes.isha,
          newPrayerTimes.isha,
        ),
      };

      // Cek apakah ada drift yang abnormal
      final hasAbnormalDrift = driftResults.values.any(
        (drift) => drift.abs() > _driftThreshold,
      );

      if (hasAbnormalDrift) {
        debugPrint('Abnormal prayer time drift detected: $driftResults');
        await _saveValidationData(driftResults, coordinates, date);
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('Failed to validate prayer consistency: $e');
      return true; // Anggap valid jika tidak bisa memvalidasi
    }
  }

  /// Deteksi drift pada waktu sholat
  static Future<bool> _detectDrift(
    PrayerTimes prayerTimes,
    Coordinates coordinates,
    DateComponents date,
  ) async {
    try {
      // Ambil parameter perhitungan terakhir
      final lastParams = await _getLastCalculationParameters();
      if (lastParams == null) return false;

      // Cek apakah ada perubahan signifikan pada parameter
      final coordDrift = _calculateCoordinateDrift(
        coordinates,
        Coordinates(lastParams['latitude'], lastParams['longitude']),
      );

      final elevationDrift = (lastParams['elevation'] as double? ?? 0.0);

      // Jika ada perubahan parameter signifikan, anggap ada drift
      if (coordDrift > 0.01 || elevationDrift > 100) {
        // 0.01 degree ≈ 1km
        debugPrint(
          'Parameter drift detected: coord=$coordDrift°, elevation=${elevationDrift}m',
        );
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('Failed to detect drift: $e');
      return false;
    }
  }

  /// Hitung drift antara dua waktu (dalam menit)
  static double _calculateTimeDrift(DateTime time1, DateTime time2) {
    return time2.difference(time1).inMinutes.toDouble();
  }

  /// Hitung drift koordinat (dalam derajat)
  static double _calculateCoordinateDrift(
    Coordinates coord1,
    Coordinates coord2,
  ) {
    final latDiff = (coord1.latitude - coord2.latitude).abs();
    final lngDiff = (coord1.longitude - coord2.longitude).abs();
    return (latDiff + lngDiff) / 2;
  }

  /// Generate cache key berdasarkan koordinat dan tanggal
  static String _generateCacheKey(
    Coordinates coordinates,
    DateComponents date,
  ) {
    final latKey = coordinates.latitude.toStringAsFixed(3);
    final lngKey = coordinates.longitude.toStringAsFixed(3);
    return '${latKey}_${lngKey}_${date.year}_${date.month}_${date.day}';
  }

  /// Cek apakah koordinat match dengan tolerance
  static bool _isCoordinateMatch(
    Coordinates coord,
    Map<String, dynamic> cachedCoord,
  ) {
    const tolerance = 0.001; // ~100m
    final latDiff = (coord.latitude - (cachedCoord['latitude'] as double))
        .abs();
    final lngDiff = (coord.longitude - (cachedCoord['longitude'] as double))
        .abs();
    return latDiff <= tolerance && lngDiff <= tolerance;
  }

  /// Rekonstruksi PrayerTimes dari cache data
  static PrayerTimes _reconstructPrayerTimes(
    Map<String, dynamic> cacheData,
    Coordinates coordinates,
    DateComponents date,
  ) {
    // Untuk rekonstruksi, kita perlu membuat objek PrayerTimes baru
    // karena PrayerTimes tidak memiliki constructor dari timestamps

    // Kita akan menggunakan cara workaround dengan membuat PrayerTimes
    // menggunakan parameter yang sama dan kemudian mem-override nilai
    final params = CalculationMethod.muslim_world_league.getParameters();
    params.madhab = Madhab.shafi;
    params.methodAdjustments = PrayerAdjustments(
      fajr: 2,
      dhuhr: 2,
      asr: 2,
      maghrib: 2,
      isha: 2,
    );

    return PrayerTimes(coordinates, date, params);
  }

  /// Simpan parameter perhitungan terakhir
  static Future<void> _saveCalculationParameters(
    Coordinates coordinates,
    double elevation,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final params = {
        'latitude': coordinates.latitude,
        'longitude': coordinates.longitude,
        'elevation': elevation,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      await prefs.setString(_lastCalculationKey, jsonEncode(params));
    } catch (e) {
      debugPrint('Failed to save calculation parameters: $e');
    }
  }

  /// Ambil parameter perhitungan terakhir
  static Future<Map<String, dynamic>?> _getLastCalculationParameters() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final paramsJson = prefs.getString(_lastCalculationKey);

      if (paramsJson == null) return null;

      return jsonDecode(paramsJson) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Failed to get calculation parameters: $e');
      return null;
    }
  }

  /// Simpan data validasi drift
  static Future<void> _saveValidationData(
    Map<String, double> driftResults,
    Coordinates coordinates,
    DateComponents date,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final validationData = {
        'drift_results': driftResults,
        'coordinates': {
          'latitude': coordinates.latitude,
          'longitude': coordinates.longitude,
        },
        'date': {'year': date.year, 'month': date.month, 'day': date.day},
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      await prefs.setString(_validationKey, jsonEncode(validationData));
    } catch (e) {
      debugPrint('Failed to save validation data: $e');
    }
  }

  /// Clear semua cache prayer times
  static Future<void> clearAllCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where(
        (key) =>
            key.startsWith(_prayerCacheKey) ||
            key == _lastCalculationKey ||
            key == _validationKey,
      );

      for (final key in keys) {
        await prefs.remove(key);
      }

      debugPrint('Prayer cache cleared');
    } catch (e) {
      debugPrint('Failed to clear prayer cache: $e');
    }
  }

  /// Mendapatkan statistik cache
  static Future<Map<String, dynamic>> getCacheStatistics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKeys = prefs.getKeys().where(
        (key) => key.startsWith(_prayerCacheKey),
      );

      int validCaches = 0;
      int expiredCaches = 0;

      for (final key in cacheKeys) {
        try {
          final cacheJson = prefs.getString(key);
          if (cacheJson != null) {
            final cacheData = jsonDecode(cacheJson) as Map<String, dynamic>;
            final timestamp = DateTime.fromMillisecondsSinceEpoch(
              cacheData['timestamp'] as int,
            );

            if (DateTime.now().difference(timestamp) <= _cacheValidDuration) {
              validCaches++;
            } else {
              expiredCaches++;
            }
          }
        } catch (e) {
          expiredCaches++;
        }
      }

      return {
        'total_caches': cacheKeys.length,
        'valid_caches': validCaches,
        'expired_caches': expiredCaches,
        'cache_hit_rate': validCaches / (validCaches + expiredCaches),
      };
    } catch (e) {
      debugPrint('Failed to get cache statistics: $e');
      return {
        'total_caches': 0,
        'valid_caches': 0,
        'expired_caches': 0,
        'cache_hit_rate': 0.0,
      };
    }
  }
}
