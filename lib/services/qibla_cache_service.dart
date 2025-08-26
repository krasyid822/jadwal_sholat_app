import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

/// Service untuk cache data Qibla untuk meningkatkan performa
class QiblaCacheService {
  static const String _keyQiblaDirection = 'qibla_direction';
  static const String _keyLocationLat = 'location_lat';
  static const String _keyLocationLng = 'location_lng';
  static const String _keyCacheTimestamp = 'qibla_cache_timestamp';

  // Cache berlaku 24 jam
  static const int _cacheValidityHours = 24;

  /// Simpan data qibla ke cache
  static Future<void> cacheQiblaData({
    required double qiblaDirection,
    required double latitude,
    required double longitude,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    await Future.wait([
      prefs.setDouble(_keyQiblaDirection, qiblaDirection),
      prefs.setDouble(_keyLocationLat, latitude),
      prefs.setDouble(_keyLocationLng, longitude),
      prefs.setInt(_keyCacheTimestamp, timestamp),
    ]);
  }

  /// Ambil data qibla dari cache jika masih valid
  static Future<QiblaCacheData?> getCachedQiblaData({
    required double currentLat,
    required double currentLng,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // Cek apakah cache ada
    if (!prefs.containsKey(_keyQiblaDirection) ||
        !prefs.containsKey(_keyLocationLat) ||
        !prefs.containsKey(_keyLocationLng) ||
        !prefs.containsKey(_keyCacheTimestamp)) {
      return null;
    }

    // Cek apakah cache masih valid (berdasarkan waktu)
    final cacheTimestamp = prefs.getInt(_keyCacheTimestamp)!;
    final cacheAge = DateTime.now().millisecondsSinceEpoch - cacheTimestamp;
    final cacheAgeHours = cacheAge / (1000 * 60 * 60);

    if (cacheAgeHours > _cacheValidityHours) {
      return null;
    }

    // Cek apakah lokasi berubah signifikan (> 100 meter)
    final cachedLat = prefs.getDouble(_keyLocationLat)!;
    final cachedLng = prefs.getDouble(_keyLocationLng)!;

    final distance = _calculateDistance(
      currentLat,
      currentLng,
      cachedLat,
      cachedLng,
    );

    // Jika jarak > 100 meter, cache tidak valid
    if (distance > 0.1) {
      return null;
    }

    // Cache valid, return data
    final qiblaDirection = prefs.getDouble(_keyQiblaDirection)!;

    return QiblaCacheData(
      qiblaDirection: qiblaDirection,
      latitude: cachedLat,
      longitude: cachedLng,
      timestamp: DateTime.fromMillisecondsSinceEpoch(cacheTimestamp),
    );
  }

  /// Hitung jarak antara dua titik koordinat dalam kilometer
  static double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double R = 6371; // Radius bumi dalam km

    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return R * c;
  }

  static double _toRadians(double degrees) {
    return degrees * (pi / 180);
  }

  /// Hapus cache qibla
  static Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_keyQiblaDirection),
      prefs.remove(_keyLocationLat),
      prefs.remove(_keyLocationLng),
      prefs.remove(_keyCacheTimestamp),
    ]);
  }
}

/// Model data cache qibla
class QiblaCacheData {
  final double qiblaDirection;
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  QiblaCacheData({
    required this.qiblaDirection,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  @override
  String toString() {
    return 'QiblaCacheData(qibla: ${qiblaDirection.toStringAsFixed(2)}°, '
        'location: ($latitude, $longitude), timestamp: $timestamp)';
  }
}
