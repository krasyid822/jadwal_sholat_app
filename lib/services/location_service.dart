import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Unified service untuk mengelola semua logika terkait lokasi GPS
/// Menggabungkan fungsi location, caching, dan accuracy dalam satu service
class LocationService {
  // Cache keys
  static const String _lastLocationKey = 'last_location';
  static const String _lastPlacemarkKey = 'last_placemark';
  static const String _locationTimestampKey = 'location_timestamp';
  static const String _cacheValidityKey = 'cache_validity_hours';

  // Accuracy keys
  static const String _latitudeKey = 'accurate_latitude';
  static const String _longitudeKey = 'accurate_longitude';
  static const String _elevationKey = 'accurate_elevation';

  // Durasi cache default (24 jam)
  static const int defaultCacheValidityHours = 24;

  /// Menentukan posisi GPS pengguna saat ini dengan caching dan accuracy tinggi
  static Future<Position> determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Periksa apakah layanan lokasi diaktifkan pada perangkat
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Coba gunakan cached location jika layanan GPS dimatikan
      final prefs = await SharedPreferences.getInstance();
      final cacheEnabled = prefs.getBool('enable_location_cache') ?? false;
      final cachedPosition = cacheEnabled ? await getCachedLocation() : null;
      if (cachedPosition != null) {
        return cachedPosition;
      }
      return Future.error('Layanan lokasi dimatikan. Harap aktifkan GPS.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Izin lokasi ditolak oleh pengguna.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error(
        'Izin lokasi ditolak permanen. Harap aktifkan dari pengaturan aplikasi.',
      );
    }

    // Dapatkan lokasi dengan akurasi tinggi
    return await getAccuratePosition();
  }

  /// Mendapatkan posisi dengan akurasi tinggi
  static Future<Position> getAccuratePosition() async {
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: locationSettings,
      );

      // Simpan posisi ke cache (jika cache diizinkan)
      final prefs = await SharedPreferences.getInstance();
      final cacheEnabled = prefs.getBool('enable_location_cache') ?? false;
      if (cacheEnabled) {
        await _savePositionData(position);
      }

      return position;
    } catch (e) {
      // Jika gagal mendapatkan posisi baru, gunakan yang tersimpan
      final storedPosition = await _getStoredPosition();
      if (storedPosition != null) {
        return storedPosition;
      }

      rethrow;
    }
  }

  /// Simpan lokasi dan placemark ke cache
  static Future<void> saveLocationWithPlacemark(
    Position position,
    Placemark placemark,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    // Simpan data posisi
    final locationData = {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'altitude': position.altitude,
      'accuracy': position.accuracy,
      'timestamp': position.timestamp.millisecondsSinceEpoch,
    };

    // Simpan data placemark
    final placemarkData = {
      'country': placemark.country ?? '',
      'administrativeArea': placemark.administrativeArea ?? '',
      'subAdministrativeArea': placemark.subAdministrativeArea ?? '',
      'locality': placemark.locality ?? '',
      'subLocality': placemark.subLocality ?? '',
      'thoroughfare': placemark.thoroughfare ?? '',
      'subThoroughfare': placemark.subThoroughfare ?? '',
      'postalCode': placemark.postalCode ?? '',
      'name': placemark.name ?? '',
    };

    await prefs.setString(_lastLocationKey, json.encode(locationData));
    await prefs.setString(_lastPlacemarkKey, json.encode(placemarkData));
    await prefs.setInt(
      _locationTimestampKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Ambil lokasi dari cache jika masih valid
  static Future<Position?> getCachedLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final cacheEnabled = prefs.getBool('enable_location_cache') ?? false;
    if (!cacheEnabled) return null;

    final locationStr = prefs.getString(_lastLocationKey);
    final timestamp = prefs.getInt(_locationTimestampKey);

    if (locationStr == null || timestamp == null) {
      return null;
    }

    // Periksa validitas cache
    final cacheValidityHours =
        prefs.getInt(_cacheValidityKey) ?? defaultCacheValidityHours;
    final cacheExpiry = DateTime.fromMillisecondsSinceEpoch(
      timestamp,
    ).add(Duration(hours: cacheValidityHours));

    if (DateTime.now().isAfter(cacheExpiry)) {
      return null; // Cache expired
    }

    try {
      final locationData = json.decode(locationStr) as Map<String, dynamic>;

      return Position(
        latitude: locationData['latitude'],
        longitude: locationData['longitude'],
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          locationData['timestamp'],
        ),
        accuracy: locationData['accuracy'],
        altitude: locationData['altitude'],
        heading: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
        altitudeAccuracy: 0.0,
        headingAccuracy: 0.0,
      );
    } catch (e) {
      return null;
    }
  }

  /// Ambil placemark dari cache
  static Future<Placemark?> getCachedPlacemark() async {
    final prefs = await SharedPreferences.getInstance();
    final cacheEnabled = prefs.getBool('enable_location_cache') ?? false;
    if (!cacheEnabled) return null;

    final placemarkStr = prefs.getString(_lastPlacemarkKey);
    if (placemarkStr == null) {
      return null;
    }

    try {
      final placemarkData = json.decode(placemarkStr) as Map<String, dynamic>;

      return Placemark(
        country: placemarkData['country'],
        administrativeArea: placemarkData['administrativeArea'],
        subAdministrativeArea: placemarkData['subAdministrativeArea'],
        locality: placemarkData['locality'],
        subLocality: placemarkData['subLocality'],
        thoroughfare: placemarkData['thoroughfare'],
        subThoroughfare: placemarkData['subThoroughfare'],
        postalCode: placemarkData['postalCode'],
        name: placemarkData['name'],
      );
    } catch (e) {
      return null;
    }
  }

  /// Set durasi validitas cache
  static Future<void> setCacheValidityHours(int hours) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_cacheValidityKey, hours);
  }

  /// Clear cache lokasi
  static Future<void> clearLocationCache() async {
    final prefs = await SharedPreferences.getInstance();
    final cacheEnabled = prefs.getBool('enable_location_cache') ?? false;
    if (!cacheEnabled) {
      debugPrint('Location cache disabled by settings, skipping clear');
      return;
    }

    await prefs.remove(_lastLocationKey);
    await prefs.remove(_lastPlacemarkKey);
    await prefs.remove(_locationTimestampKey);
  }

  /// Private method untuk menyimpan posisi akurat
  static Future<void> _savePositionData(Position position) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheEnabled = prefs.getBool('enable_location_cache') ?? false;
    if (!cacheEnabled) return;

    await prefs.setDouble(_latitudeKey, position.latitude);
    await prefs.setDouble(_longitudeKey, position.longitude);
    await prefs.setDouble(_elevationKey, position.altitude);
    await prefs.setInt(
      _locationTimestampKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Private method untuk mendapatkan posisi tersimpan
  static Future<Position?> _getStoredPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final cacheEnabled = prefs.getBool('enable_location_cache') ?? false;
    if (!cacheEnabled) return null;

    final latitude = prefs.getDouble(_latitudeKey);
    final longitude = prefs.getDouble(_longitudeKey);
    final elevation = prefs.getDouble(_elevationKey);

    if (latitude == null || longitude == null) {
      return null;
    }

    return Position(
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.now(),
      accuracy: 10.0,
      altitude: elevation ?? 0.0,
      heading: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
      altitudeAccuracy: 0.0,
      headingAccuracy: 0.0,
    );
  }

  /// Validasi apakah koordinat berada di Indonesia
  static bool isValidIndonesianCoordinate(double latitude, double longitude) {
    // Batas koordinat Indonesia (approximation)
    // Latitude: -11.0 to 6.0
    // Longitude: 95.0 to 141.0
    return latitude >= -11.0 &&
        latitude <= 6.0 &&
        longitude >= 95.0 &&
        longitude <= 141.0;
  }

  /// Mendapatkan elevasi dari koordinat (stub - bisa dikembangkan dengan API)
  static Future<double> getElevation(double latitude, double longitude) async {
    // Implementasi sederhana - bisa dikembangkan dengan elevation API
    return 0.0;
  }

  /// Force refresh - hapus cache dan ambil lokasi baru
  static Future<void> forceRefresh() async {
    await clearLocationCache();
  }
}
