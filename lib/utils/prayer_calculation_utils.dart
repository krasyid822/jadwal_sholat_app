import 'dart:math';

import 'package:adhan/adhan.dart';
import 'package:geolocator/geolocator.dart';
import '../services/elevation_service.dart';
import '../services/prayer_cache_service.dart';

/// Utilitas untuk kalkulasi waktu sholat yang akurat mengikuti standar Kemenag RI
class PrayerCalculationUtils {
  /// Membuat parameter kalkulasi yang akurat untuk Indonesia
  static CalculationParameters createKemenagParameters() {
    final params = CalculationMethod.other.getParameters();

    // Parameter standar Kemenag RI
    params.fajrAngle = 20.0; // Sudut fajar untuk Subuh
    params.ishaAngle = 18.0; // Sudut senja untuk Isya

    // Koreksi waktu berdasarkan pengamatan empiris Kemenag
    params.methodAdjustments = PrayerAdjustments(
      fajr: 2, // Subuh +2 menit
      dhuhr: 2, // Dzuhur +2 menit
      asr: 2, // Ashar +2 menit
      maghrib: 2, // Maghrib +2 menit
      isha: 2, // Isya +2 menit
    );

    // Mazhab Syafi'i (standar Indonesia)
    params.madhab = Madhab.shafi;

    return params;
  }

  /// Menghitung waktu sholat dengan koreksi elevasi yang akurat dan cache offline
  static Future<PrayerTimes> calculatePrayerTimesEnhanced(
    Coordinates coordinates,
    DateComponents date, {
    double? elevation,
    String? cityName,
    bool useCache = true,
  }) async {
    try {
      // Coba ambil dari cache terlebih dahulu jika menggunakan cache
      if (useCache) {
        final cachedPrayerTimes = await PrayerCacheService.getCachedPrayerTimes(
          coordinates,
          date,
        );
        if (cachedPrayerTimes != null) {
          return cachedPrayerTimes;
        }
      }

      // Dapatkan elevasi yang akurat
      double actualElevation;
      if (elevation != null && elevation > 0) {
        actualElevation = elevation;
      } else {
        // Gunakan ElevationService untuk mendapatkan elevasi yang akurat
        final dummyPosition = Position(
          latitude: coordinates.latitude,
          longitude: coordinates.longitude,
          timestamp: DateTime.now(),
          accuracy: 10.0,
          altitude: elevation ?? 0.0,
          altitudeAccuracy: 0.0,
          heading: 0.0,
          headingAccuracy: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
        );
        actualElevation = await ElevationService.getAccurateElevation(
          dummyPosition,
          cityName: cityName,
        );
      }

      final params = createKemenagParameters();

      // Koreksi berdasarkan elevasi yang lebih akurat
      if (actualElevation > 0) {
        // Formula koreksi elevasi yang ditingkatkan
        // Menggunakan rumus geometris yang lebih akurat
        final earthRadius = 6371000.0; // meter
        final elevationRadians = actualElevation / earthRadius;

        // Koreksi sudut berdasarkan elevasi untuk maghrib dan isha
        final horizonCorrection =
            sqrt(2 * elevationRadians) * 57.2958; // dalam derajat

        // Untuk tempat tinggi, matahari terbenam lebih lambat dan isya lebih cepat
        final maghribAdjustment =
            2 + (horizonCorrection * 3.5).round(); // 3.5 menit per derajat
        final ishaAdjustment =
            2 - (horizonCorrection * 0.5).round(); // kompensasi untuk isha

        params.methodAdjustments = PrayerAdjustments(
          fajr: 2,
          dhuhr: 2,
          asr: 2,
          maghrib: maghribAdjustment,
          isha: max(2, ishaAdjustment), // pastikan minimal 2 menit
        );
      }

      final prayerTimes = PrayerTimes(coordinates, date, params);

      // Validasi konsistensi untuk mencegah drift
      final isConsistent = await PrayerCacheService.validatePrayerConsistency(
        prayerTimes,
        coordinates,
        date,
      );
      if (!isConsistent) {
        // Jika ada drift, gunakan parameter yang lebih konservatif
        final conservativeParams = createKemenagParameters();
        conservativeParams.methodAdjustments = PrayerAdjustments(
          fajr: 2,
          dhuhr: 2,
          asr: 2,
          maghrib: 2,
          isha: 2,
        );
        final conservativePrayerTimes = PrayerTimes(
          coordinates,
          date,
          conservativeParams,
        );

        // Cache hasil konservatif
        if (useCache) {
          await PrayerCacheService.cachePrayerTimes(
            conservativePrayerTimes,
            coordinates,
            date,
            actualElevation,
          );
        }

        return conservativePrayerTimes;
      }

      // Cache hasil perhitungan
      if (useCache) {
        await PrayerCacheService.cachePrayerTimes(
          prayerTimes,
          coordinates,
          date,
          actualElevation,
        );
      }

      return prayerTimes;
    } catch (e) {
      // Fallback ke perhitungan sederhana jika terjadi error
      final params = createKemenagParameters();
      return PrayerTimes(coordinates, date, params);
    }
  }

  /// Versi sinkron untuk kompatibilitas backward (DEPRECATED - gunakan versi async)
  @Deprecated(
    'Use calculatePrayerTimesEnhanced instead for better accuracy and caching',
  )
  static PrayerTimes calculatePrayerTimesSync(
    Coordinates coordinates,
    DateComponents date, {
    double elevation = 0.0,
  }) {
    final params = createKemenagParameters();

    // Koreksi berdasarkan elevasi (implementasi sederhana)
    if (elevation > 0) {
      final elevationCorrection = (elevation / 6371000) * 57.2958;

      params.methodAdjustments = PrayerAdjustments(
        fajr: 2,
        dhuhr: 2,
        asr: 2,
        maghrib: 2 + (elevationCorrection * 4).round(),
        isha: 2,
      );
    }

    return PrayerTimes(coordinates, date, params);
  }

  /// Alias untuk backward compatibility dengan perbaikan elevasi
  @Deprecated(
    'Use calculatePrayerTimesEnhanced instead for better accuracy and offline caching',
  )
  static PrayerTimes calculatePrayerTimes(
    Coordinates coordinates,
    DateComponents date, {
    double elevation = 0.0,
  }) {
    final params = createKemenagParameters();

    // Perbaikan untuk elevasi 0: gunakan estimasi berdasarkan lokasi
    double actualElevation = elevation;
    if (elevation <= 0.0) {
      actualElevation = _estimateElevationByCoordinates(
        coordinates.latitude,
        coordinates.longitude,
      );
    }

    // Koreksi berdasarkan elevasi yang diperbaiki
    if (actualElevation > 0) {
      final elevationCorrection = (actualElevation / 6371000) * 57.2958;

      params.methodAdjustments = PrayerAdjustments(
        fajr: 2,
        dhuhr: 2,
        asr: 2,
        maghrib: 2 + (elevationCorrection * 4).round(),
        isha: 2,
      );
    }

    return PrayerTimes(coordinates, date, params);
  }

  /// Estimasi elevasi berdasarkan koordinat (untuk fallback saat elevasi 0)
  static double _estimateElevationByCoordinates(
    double latitude,
    double longitude,
  ) {
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

  /// Menghitung waktu Imsak (10 menit sebelum Subuh)
  static DateTime calculateImsak(DateTime fajrTime) {
    return fajrTime.subtract(const Duration(minutes: 10));
  }

  /// Menghitung waktu Dhuha (15 menit setelah Terbit)
  static DateTime calculateDhuha(DateTime sunriseTime) {
    return sunriseTime.add(const Duration(minutes: 15));
  }

  /// Menghitung waktu Tahajud (sepertiga malam terakhir)
  static DateTime calculateTahajud(DateTime maghribTime, DateTime fajrTime) {
    final nightDuration = fajrTime.difference(maghribTime);
    final oneThirdNight = Duration(
      milliseconds: (nightDuration.inMilliseconds / 3).round(),
    );
    return fajrTime.subtract(oneThirdNight);
  }

  /// Validasi dan koreksi zona waktu
  static DateTime adjustForTimeZone(DateTime prayerTime, String timeZoneId) {
    // Implementasi koreksi zona waktu jika diperlukan
    // Untuk saat ini, mengembalikan waktu asli
    return prayerTime;
  }

  /// Menentukan apakah waktu saat ini adalah waktu sholat yang makruh
  static bool isMakruhTime(DateTime currentTime, PrayerTimes prayerTimes) {
    // Waktu makruh:
    // 1. Setelah Subuh sampai matahari naik (15 menit setelah terbit)
    // 2. Ketika matahari tepat di atas kepala (15 menit sebelum-sesudah Dzuhur)
    // 3. Setelah Ashar sampai Maghrib

    final afterSubuh =
        currentTime.isAfter(prayerTimes.fajr) &&
        currentTime.isBefore(
          prayerTimes.sunrise.add(const Duration(minutes: 15)),
        );

    final beforeDzuhur =
        currentTime.isAfter(
          prayerTimes.dhuhr.subtract(const Duration(minutes: 15)),
        ) &&
        currentTime.isBefore(
          prayerTimes.dhuhr.add(const Duration(minutes: 15)),
        );

    final afterAshar =
        currentTime.isAfter(prayerTimes.asr) &&
        currentTime.isBefore(prayerTimes.maghrib);

    return afterSubuh || beforeDzuhur || afterAshar;
  }

  /// Menghitung qibla direction dengan akurasi tinggi
  static double calculateQiblaDirection(double latitude, double longitude) {
    // Koordinat Ka'bah di Makkah
    const double kaabaLat = 21.4225;
    const double kaabaLon = 39.8262;

    // Konversi ke radian
    final lat1 = latitude * (3.14159265359 / 180);
    final lat2 = kaabaLat * (3.14159265359 / 180);
    final deltaLon = (kaabaLon - longitude) * (3.14159265359 / 180);

    // Rumus bearing
    final y = sin(deltaLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon);

    double bearing = atan2(y, x);

    // Konversi ke derajat dan normalisasi (0-360)
    bearing = bearing * (180 / 3.14159265359);
    bearing = (bearing + 360) % 360;

    return bearing;
  }
}
