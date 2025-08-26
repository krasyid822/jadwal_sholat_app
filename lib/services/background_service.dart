import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:adhan/adhan.dart';

import 'package:jadwal_sholat_app/services/notification_service_enhanced.dart';
import 'package:jadwal_sholat_app/services/location_accuracy_service.dart';
import 'package:jadwal_sholat_app/services/location_cache_service.dart';
import 'package:jadwal_sholat_app/services/elevation_service.dart';
import 'package:jadwal_sholat_app/utils/prayer_calculation_utils.dart';

// Inisialisasi service di main.dart
Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  // Konfigurasi Notifikasi Channel untuk Service
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'foreground_service_channel',
    'Jadwal Sholat Background Service',
    description: 'Layanan refresh lokasi otomatis setiap jam.',
    importance: Importance.low,
  );

  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false, // Hanya start jika diaktifkan pengguna
      isForegroundMode: true,
      notificationChannelId: 'foreground_service_channel',
      initialNotificationTitle: 'Layanan Refresh Lokasi',
      initialNotificationContent: 'Refresh otomatis setiap jam',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

// Entry point untuk iOS background
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

// Main service function
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Pastikan binding siap
  DartPluginRegistrant.ensureInitialized();

  // Timer untuk refresh setiap jam
  Timer? refreshTimer;

  // Fungsi untuk refresh lokasi dan jadwal
  Future<void> refreshLocationAndSchedule() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final autoRefreshEnabled =
          prefs.getBool('auto_location_refresh') ?? false;

      if (!autoRefreshEnabled) {
        debugPrint('Auto refresh disabled, skipping...');
        return;
      }

      debugPrint('Starting background location refresh...');

      // Dapatkan posisi terbaru
      Position position;
      try {
        position = await LocationAccuracyService.getAccuratePosition();
      } catch (e) {
        debugPrint('Failed to get new position: $e');
        // Coba gunakan cache jika ada
        final cachedLocation = await LocationCacheService.getCachedLocation();
        if (cachedLocation != null) {
          position = cachedLocation['position'];
          debugPrint('Using cached position for background refresh');
        } else {
          return; // Skip jika tidak ada lokasi
        }
      }

      // Validasi koordinat Indonesia
      if (!LocationAccuracyService.isValidIndonesianCoordinate(position)) {
        debugPrint('Invalid coordinates for Indonesia');
        return;
      }

      // Dapatkan placemark
      List<Placemark> placemarks;
      try {
        placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
      } catch (e) {
        debugPrint('Failed to get placemark: $e');
        placemarks = [];
      }

      // Simpan ke cache
      if (placemarks.isNotEmpty) {
        await LocationCacheService.cacheLocation(
          position: position,
          placemark: placemarks[0],
        );
        debugPrint('Location updated in background and cached');
      }

      // Hitung ulang jadwal sholat
      final myCoordinates = Coordinates(position.latitude, position.longitude);

      double elevation = position.altitude;
      if (elevation <= 0.0) {
        try {
          elevation = await ElevationService.getAccurateElevation(position);
        } catch (e) {
          elevation = 0.0;
        }
      }

      final prayerTimes =
          await PrayerCalculationUtils.calculatePrayerTimesEnhanced(
            myCoordinates,
            DateComponents.from(DateTime.now()),
            elevation: elevation,
          );

      // Jadwalkan ulang notifikasi
      await NotificationServiceEnhanced.scheduleEnhancedDailyNotifications(
        prayerTimes,
      );

      debugPrint('Background refresh completed successfully');
    } catch (e) {
      debugPrint('Background refresh failed: $e');
    }
  }

  // Listen untuk perintah dari UI
  service.on('stopService').listen((event) {
    refreshTimer?.cancel();
    service.stopSelf();
    debugPrint('Background service stopped');
  });

  service.on('refreshNow').listen((event) async {
    await refreshLocationAndSchedule();
  });

  // Setup timer untuk refresh setiap jam
  refreshTimer = Timer.periodic(const Duration(hours: 1), (timer) async {
    await refreshLocationAndSchedule();
  });

  // Lakukan refresh pertama setelah 5 menit
  Timer(const Duration(minutes: 5), () async {
    await refreshLocationAndSchedule();
  });

  debugPrint('Background service started successfully');
}
