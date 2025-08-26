import 'dart:async';
import 'dart:ui';
import 'package:flutter/services.dart';

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
import 'package:jadwal_sholat_app/services/error_logger.dart';

@pragma('vm:entry-point')
class BackgroundServiceEnhanced {
  static const String _serviceChannelId = 'foreground_service_enhanced_channel';
  static const int _serviceNotificationId = 888;

  /// Inisialisasi enhanced background service
  @pragma('vm:entry-point')
  static Future<void> initializeEnhancedService() async {
    final service = FlutterBackgroundService();

    // Konfigurasi Notifikasi Channel untuk Enhanced Service
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _serviceChannelId,
      'Layanan Sholat Enhanced',
      description:
          'Layanan latar belakang untuk notifikasi sholat, countdown, dan refresh lokasi otomatis.',
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
        onStart: onStartEnhanced,
        autoStart: false, // Hanya start jika diaktifkan pengguna
        isForegroundMode: true,
        notificationChannelId: _serviceChannelId,
        initialNotificationTitle: 'Layanan Sholat Aktif',
        initialNotificationContent:
            'Menjalankan notifikasi sholat dan countdown',
        foregroundServiceNotificationId: _serviceNotificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStartEnhanced,
        onBackground: onIosBackgroundEnhanced,
      ),
    );
  }

  /// Entry point untuk iOS background enhanced
  @pragma('vm:entry-point')
  static Future<bool> onIosBackgroundEnhanced(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    return true;
  }

  /// Main enhanced service function
  @pragma('vm:entry-point')
  static void onStartEnhanced(ServiceInstance service) async {
    // Pastikan binding siap
    DartPluginRegistrant.ensureInitialized();

    // Timer untuk berbagai tugas
    Timer? hourlyRefreshTimer;
    Timer? countdownCheckTimer;
    Timer? dailyNotificationRefreshTimer;
    Timer? prayerTimeCheckTimer;
    Timer? watchdogTimer;
    Timer? heartbeatTimer;

    // Status service
    bool isServiceRunning = true;

    // Update initial notification
    await _updateServiceNotification(
      'Layanan dimulai - Menyiapkan notifikasi sholat...',
    );

    debugPrint('Enhanced background service started');

    // Timer untuk cek waktu sholat dan auto-play audio setiap 30 detik
    prayerTimeCheckTimer = Timer.periodic(const Duration(seconds: 30), (
      timer,
    ) async {
      if (!isServiceRunning) return;
      await _checkPrayerTimeAndAutoPlay();
    });

    // Timer untuk refresh lokasi setiap jam (jika diaktifkan)
    hourlyRefreshTimer = Timer.periodic(const Duration(hours: 1), (
      timer,
    ) async {
      if (!isServiceRunning) return;
      await _performHourlyLocationRefresh();
    });

    // Timer untuk cek countdown setiap menit
    countdownCheckTimer = Timer.periodic(const Duration(minutes: 1), (
      timer,
    ) async {
      if (!isServiceRunning) return;
      await _checkAndStartCountdown();
    });

    // Timer untuk refresh notifikasi harian setiap 24 jam
    dailyNotificationRefreshTimer = Timer.periodic(const Duration(hours: 24), (
      timer,
    ) async {
      if (!isServiceRunning) return;
      await _performDailyNotificationRefresh();
      await _updateServiceNotification(
        'Notifikasi harian diperbarui - ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
      );
    });

    // Listen untuk stop service
    service.on('stop').listen((event) {
      debugPrint('Enhanced background service stop requested');
      isServiceRunning = false;
      hourlyRefreshTimer?.cancel();
      countdownCheckTimer?.cancel();
      dailyNotificationRefreshTimer?.cancel();
      prayerTimeCheckTimer?.cancel();
      watchdogTimer?.cancel();
      heartbeatTimer?.cancel();
      service.stopSelf();
    });

    // Initial setup - refresh notifications
    await _performDailyNotificationRefresh();
    await _updateServiceNotification(
      'Aktif - Notifikasi sholat dan countdown siap',
    );

    // Watchdog: this background isolate is the service itself — avoid calling the
    // FlutterBackgroundService plugin method here (it may not be available in the
    // background isolate and causes MissingPluginException). Instead, keep a
    // lightweight timer for local checks/logging. Native watchdogs handle restarts.
    try {
      final prefs = await SharedPreferences.getInstance();
      final watchdogEnabled = prefs.getBool('enable_watchdog_restart') ?? true;
      if (watchdogEnabled) {
        watchdogTimer = Timer.periodic(const Duration(seconds: 30), (
          timer,
        ) async {
          try {
            // Avoid calling plugin APIs which may not be registered in the isolate.
            debugPrint('Background watchdog tick - service appears alive');
          } catch (e) {
            debugPrint('Watchdog check error: $e');
          }
        });
      } else {
        debugPrint('Watchdog disabled by settings');
      }
    } catch (e) {
      debugPrint('Error reading watchdog preference: $e');
    }

    // Heartbeat: record a timestamp to SharedPreferences every minute so native
    // watchdogs can verify Flutter health without requiring a platform channel
    // handler to be registered in the isolate.
    try {
      heartbeatTimer = Timer.periodic(const Duration(minutes: 1), (t) async {
        try {
          final prefs = await SharedPreferences.getInstance();
          final ts = DateTime.now().millisecondsSinceEpoch;
          await prefs.setInt('flutter_last_heartbeat_ms', ts);
          debugPrint('Heartbeat saved to SharedPreferences: $ts');
        } catch (e) {
          debugPrint('Failed to save heartbeat to prefs: $e');
        }
      });
    } catch (e) {
      debugPrint('Failed to initialize heartbeat timer: $e');
    }

    // Register probe handler so native can call into Flutter and expect a quick reply
    try {
      final MethodChannel probeChannel = MethodChannel(
        'jadwalsholat.rasyid/health_probe',
      );
      probeChannel.setMethodCallHandler((call) async {
        if (call.method == 'probe') {
          // Respond quickly indicating background isolate is alive
          return 'ok';
        }
        return null;
      });
      debugPrint('Probe method channel handler registered');
    } catch (e) {
      debugPrint('Failed to register probe handler: $e');
    }

    debugPrint('Enhanced background service initialized completely');
  }

  /// Refresh lokasi setiap jam jika diaktifkan
  static Future<void> _performHourlyLocationRefresh() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final autoRefreshEnabled =
          prefs.getBool('auto_location_refresh') ?? false;

      if (!autoRefreshEnabled) {
        debugPrint('Auto location refresh disabled, skipping...');
        return;
      }

      debugPrint('Performing hourly location refresh...');

      // Update service notification
      await _updateServiceNotification(
        'Memperbarui lokasi - ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
      );

      // Dapatkan posisi terbaru
      Position position;
      try {
        position = await LocationAccuracyService.getAccuratePosition();
        debugPrint(
          'New position obtained: ${position.latitude}, ${position.longitude}',
        );
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

      // Simpan lokasi terbaru
      await prefs.setDouble('last_latitude', position.latitude);
      await prefs.setDouble('last_longitude', position.longitude);

      // Cache lokasi
      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        final placemark = placemarks.first;

        await LocationCacheService.cacheLocation(
          position: position,
          placemark: placemark,
        );
      } catch (e) {
        debugPrint('Failed to geocode position: $e');
      }

      // Hitung ulang waktu sholat dan perbarui notifikasi
      await _recalculatePrayerTimesAndUpdateNotifications(position);

      await _updateServiceNotification(
        'Lokasi diperbarui - Notifikasi sholat disegarkan',
      );

      debugPrint('Hourly location refresh completed successfully');
    } catch (e) {
      debugPrint('Error in hourly location refresh: $e');
      await _updateServiceNotification(
        'Error refresh lokasi - Menggunakan lokasi tersimpan',
      );
    }
  }

  /// Cek dan mulai countdown jika mendekati waktu sholat
  static Future<void> _checkAndStartCountdown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final countdownEnabled = prefs.getBool('countdown_notifications') ?? true;

      if (!countdownEnabled) return;

      final latitude = prefs.getDouble('last_latitude');
      final longitude = prefs.getDouble('last_longitude');

      if (latitude == null || longitude == null) return;

      // Hitung waktu sholat hari ini
      final coordinates = Coordinates(latitude, longitude);
      final params = CalculationMethod.muslim_world_league.getParameters();
      params.madhab = Madhab.shafi;

      final today = DateTime.now();
      final dateComponents = DateComponents(today.year, today.month, today.day);
      final prayerTimes = PrayerTimes(coordinates, dateComponents, params);

      final now = DateTime.now();
      final prayerTimesMap = {
        'Subuh': prayerTimes.fajr,
        'Dzuhur': prayerTimes.dhuhr,
        'Ashar': prayerTimes.asr,
        'Maghrib': prayerTimes.maghrib,
        'Isya': prayerTimes.isha,
      };

      // Cek apakah ada sholat dalam 10 menit
      for (final entry in prayerTimesMap.entries) {
        final prayerName = entry.key;
        final prayerTime = entry.value;
        final difference = prayerTime.difference(now);

        // Jika dalam 10 menit dan belum dimulai countdown
        if (difference.inMinutes <= 10 && difference.inMinutes > 0) {
          // Cek apakah countdown sudah berjalan untuk sholat ini
          if (!NotificationServiceEnhanced.isCountdownActive ||
              NotificationServiceEnhanced.currentCountdownPrayer !=
                  prayerName) {
            debugPrint(
              'Starting countdown for $prayerName (${difference.inMinutes} minutes remaining)',
            );
            await NotificationServiceEnhanced.startLiveCountdown(
              prayerName,
              prayerTime,
            );

            await _updateServiceNotification(
              'Countdown $prayerName dimulai - ${difference.inMinutes} menit lagi',
            );
          }
          break; // Hanya satu countdown pada satu waktu
        }
      }
    } catch (e) {
      debugPrint('Error checking countdown: $e');
    }
  }

  /// Refresh notifikasi harian
  static Future<void> _performDailyNotificationRefresh() async {
    try {
      debugPrint('Performing daily notification refresh...');

      final prefs = await SharedPreferences.getInstance();
      final latitude = prefs.getDouble('last_latitude');
      final longitude = prefs.getDouble('last_longitude');

      if (latitude == null || longitude == null) {
        debugPrint('No location data for notification refresh');
        return;
      }

      // Hitung waktu sholat untuk hari ini dan besok
      final coordinates = Coordinates(latitude, longitude);
      final params = CalculationMethod.muslim_world_league.getParameters();
      params.madhab = Madhab.shafi;

      // Hari ini
      final today = DateTime.now();
      final todayDateComponents = DateComponents(
        today.year,
        today.month,
        today.day,
      );
      final todayPrayerTimes = PrayerTimes(
        coordinates,
        todayDateComponents,
        params,
      );

      // Besok
      final tomorrow = today.add(const Duration(days: 1));
      final tomorrowDateComponents = DateComponents(
        tomorrow.year,
        tomorrow.month,
        tomorrow.day,
      );
      final tomorrowPrayerTimes = PrayerTimes(
        coordinates,
        tomorrowDateComponents,
        params,
      );

      // Schedule ulang semua notifikasi
      await NotificationServiceEnhanced.scheduleEnhancedDailyNotifications(
        todayPrayerTimes,
      );
      await NotificationServiceEnhanced.scheduleEnhancedDailyNotifications(
        tomorrowPrayerTimes,
      );

      await prefs.setInt(
        'last_notification_refresh',
        DateTime.now().millisecondsSinceEpoch,
      );

      debugPrint('Daily notification refresh completed');
    } catch (e) {
      debugPrint('Error in daily notification refresh: $e');
    }
  }

  /// Hitung ulang waktu sholat dan update notifikasi
  static Future<void> _recalculatePrayerTimesAndUpdateNotifications(
    Position position,
  ) async {
    try {
      final coordinates = Coordinates(position.latitude, position.longitude);
      final params = CalculationMethod.muslim_world_league.getParameters();
      params.madhab = Madhab.shafi;

      // Hitung untuk hari ini dan besok
      final today = DateTime.now();
      final todayDateComponents = DateComponents(
        today.year,
        today.month,
        today.day,
      );
      final todayPrayerTimes = PrayerTimes(
        coordinates,
        todayDateComponents,
        params,
      );

      final tomorrow = today.add(const Duration(days: 1));
      final tomorrowDateComponents = DateComponents(
        tomorrow.year,
        tomorrow.month,
        tomorrow.day,
      );
      final tomorrowPrayerTimes = PrayerTimes(
        coordinates,
        tomorrowDateComponents,
        params,
      );

      // Update notifikasi dengan waktu yang baru
      await NotificationServiceEnhanced.scheduleEnhancedDailyNotifications(
        todayPrayerTimes,
      );
      await NotificationServiceEnhanced.scheduleEnhancedDailyNotifications(
        tomorrowPrayerTimes,
      );

      debugPrint('Prayer times recalculated and notifications updated');
    } catch (e) {
      debugPrint('Error recalculating prayer times: $e');
    }
  }

  /// Update service notification dengan status
  static Future<void> _updateServiceNotification(String content) async {
    try {
      await NotificationServiceEnhanced.updateForegroundServiceNotification(
        content,
      );
    } catch (e) {
      debugPrint('Error updating service notification: $e');
    }
  }

  /// Start enhanced background service
  static Future<bool> startEnhancedService() async {
    try {
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();

      if (isRunning) {
        debugPrint('Enhanced background service already running');
        return true;
      }

      await service.startService();
      debugPrint('Enhanced background service started');
      return true;
    } catch (e) {
      debugPrint('Error starting enhanced background service: $e');
      return false;
    }
  }

  /// Stop enhanced background service
  static Future<bool> stopEnhancedService() async {
    try {
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();

      if (!isRunning) {
        debugPrint('Enhanced background service not running');
        return true;
      }

      service.invoke('stop');
      await NotificationServiceEnhanced.hideForegroundServiceNotification();
      debugPrint('Enhanced background service stopped');
      return true;
    } catch (e) {
      debugPrint('Error stopping enhanced background service: $e');
      return false;
    }
  }

  /// Cek apakah service sedang berjalan
  static Future<bool> isServiceRunning() async {
    try {
      final service = FlutterBackgroundService();
      return await service.isRunning();
    } catch (e) {
      debugPrint('Error checking service status: $e');
      return false;
    }
  }

  /// Cek waktu sholat dan auto-play audio jika sudah waktunya
  static Future<void> _checkPrayerTimeAndAutoPlay() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Cek apakah auto-play audio diaktifkan
      final autoPlayEnabled = prefs.getBool('auto_play_adhan_audio') ?? true;
      if (!autoPlayEnabled) {
        debugPrint('⏸️ Auto-play disabled in settings, skipping check');
        return; // Skip jika auto-play tidak diaktifkan
      }

      final now = DateTime.now();
      debugPrint(
        '⏰ Checking prayer times for auto-play at ${now.hour}:${now.minute}:${now.second}',
      );

      // List waktu sholat untuk dicek
      final prayers = ['Subuh', 'Dzuhur', 'Ashar', 'Maghrib', 'Isya'];

      for (final prayer in prayers) {
        // Cek apakah audio sudah diputar untuk waktu sholat hari ini
        final audioPlayedKey =
            'audio_played_${prayer.toLowerCase()}_${now.year}_${now.month}_${now.day}';
        final audioAlreadyPlayed = prefs.getBool(audioPlayedKey) ?? false;

        if (audioAlreadyPlayed) {
          // debugPrint('✅ Audio already played for $prayer today');
          continue;
        }

        // Get waktu sholat yang disimpan
        final prayerTimeKey = 'prayer_time_${prayer.toLowerCase()}';
        final prayerTimeString = prefs.getString(prayerTimeKey);

        if (prayerTimeString != null) {
          final prayerTime = DateTime.parse(prayerTimeString);
          final timeDiff = now.difference(prayerTime).inSeconds;

          debugPrint(
            '🕐 $prayer: scheduled at ${prayerTime.hour}:${prayerTime.minute}, diff: ${timeDiff}s',
          );

          // Jika waktu sekarang sudah melewati waktu sholat 0-60 detik, auto play
          if (timeDiff >= 0 && timeDiff <= 60) {
            debugPrint(
              '🎵 TRIGGERING auto-play for $prayer - time difference: ${timeDiff}s',
            );

            // Play audio adzan
            await NotificationServiceEnhanced.playFullAdhanAudio(prayer);

            // Mark sebagai sudah diputar
            await prefs.setBool(audioPlayedKey, true);
            debugPrint('✅ Marked $prayer as audio played for today');

            // Update service notification
            await _updateServiceNotification(
              'Audio azan $prayer sedang diputar otomatis',
            );

            // Update notification status
            await _updatePrayerNotificationStatus(
              prayer,
              'Audio azan sedang diputar otomatis...',
            );

            // Break setelah memutar satu audio
            break;
          } else if (timeDiff < 0) {
            final minutesToPrayer = (timeDiff.abs() / 60).round();
            if (minutesToPrayer <= 5) {
              // Only log jika dalam 5 menit
              debugPrint('⏳ $prayer in $minutesToPrayer minutes');
            }
          }
        } else {
          debugPrint('❌ No prayer time stored for $prayer');
        }
      }
    } catch (e) {
      debugPrint('❌ Error checking prayer time for auto play: $e');
      await ErrorLogger.instance.logError(
        message: 'Error in _checkPrayerTimeAndAutoPlay',
        error: e,
        stackTrace: StackTrace.current,
        context: 'background_service_prayer_check',
      );
    }
  }

  /// Update status notifikasi prayer dengan pesan khusus
  static Future<void> _updatePrayerNotificationStatus(
    String prayerName,
    String status,
  ) async {
    try {
      // Call method dari NotificationServiceEnhanced
      await NotificationServiceEnhanced.updateNotificationWithAudioStatus(
        prayerName,
        status,
      );
    } catch (e) {
      debugPrint('Error updating prayer notification status: $e');
    }
  }

  /// Restart enhanced service
  static Future<bool> restartEnhancedService() async {
    try {
      await stopEnhancedService();
      await Future.delayed(const Duration(seconds: 2));
      return await startEnhancedService();
    } catch (e) {
      debugPrint('Error restarting enhanced service: $e');
      return false;
    }
  }
}
