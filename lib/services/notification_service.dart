import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:adhan/adhan.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';
import 'error_logger.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Audio player untuk adzan
  static final AudioPlayer _audioPlayer = AudioPlayer();

  // Channel notifikasi yang disederhanakan
  static const String _prayerChannelId = 'prayer_channel';
  static const String _countdownChannelId = 'countdown_channel';

  // Timer untuk countdown
  static Timer? _countdownTimer;

  // Method channel untuk AlarmManager (XOS/Infinix compatibility)
  static const MethodChannel _alarmChannel = MethodChannel(
    'jadwalsholat.rasyid/alarm',
  );

  /// Inisialisasi plugin notifikasi
  static Future<bool> initialize() async {
    try {
      // Inisialisasi pengaturan Android
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );

      // Inisialisasi pengaturan umum
      const initSettings = InitializationSettings(android: androidSettings);

      // Inisialisasi plugin
      await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Buat channel notifikasi
      await _createNotificationChannels();

      debugPrint('NotificationService initialized');
      return true;
    } catch (e, stackTrace) {
      debugPrint('Error initializing notifications: $e');
      await ErrorLogger.instance.logError(
        message: 'Failed to initialize notifications',
        error: e,
        stackTrace: stackTrace,
        context: 'notification_initialization',
      );
      return false;
    }
  }

  /// Callback saat notifikasi ditekan
  static void _onNotificationTapped(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.payload}');

    if (response.payload != null) {
      if (response.payload!.contains('prayer:')) {
        // Notifikasi waktu sholat - play audio adzan
        final prayerName = response.payload!.split(':')[1];
        playAdhanAudio(prayerName);
      } else if (response.payload!.contains('countdown:')) {
        // Notifikasi countdown - tidak play audio, hanya log
        final prayerName = response.payload!.split(':')[1];
        debugPrint('Countdown notification for $prayerName tapped');
      } else if (response.payload!.contains('test:')) {
        // Test notification - play short audio adzan biasa
        debugPrint('Test notification tapped - playing test audio');
        playAdhanAudio('Dzuhur'); // Play audio test dengan adzan biasa
      }
    }
  }

  /// Membuat channel notifikasi yang diperlukan
  static Future<void> _createNotificationChannels() async {
    try {
      // Channel untuk notifikasi utama waktu sholat
      const prayerChannel = AndroidNotificationChannel(
        _prayerChannelId,
        'Notifikasi Sholat',
        description: 'Notifikasi untuk waktu sholat wajib.',
        importance: Importance.high,
        enableVibration: true,
        showBadge: true,
        playSound: true,
      );

      // Channel untuk countdown 10 menit sebelum sholat
      const countdownChannel = AndroidNotificationChannel(
        _countdownChannelId,
        'Countdown Sholat',
        description: 'Channel untuk countdown 10 menit sebelum waktu sholat.',
        importance: Importance.low,
        enableVibration: false,
        showBadge: false,
        playSound: false,
      );

      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(prayerChannel);

      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(countdownChannel);
    } catch (e, stackTrace) {
      debugPrint('Error creating notification channels: $e');
      await ErrorLogger.instance.logError(
        message: 'Failed to create notification channels',
        error: e,
        stackTrace: stackTrace,
        context: 'notification_channel_creation',
      );
    }
  }

  /// Cek dan minta permission notifikasi
  static Future<bool> requestPermissions() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        bool allPermissionsGranted = true;

        // Request notification permission (Android 13+)
        final notificationStatus = await Permission.notification.request();
        if (!notificationStatus.isGranted) {
          debugPrint('Notification permission denied');
          allPermissionsGranted = false;
        }

        // Request exact alarm permission (Android 12+)
        final exactAlarmStatus = await Permission.scheduleExactAlarm.status;
        if (exactAlarmStatus.isDenied) {
          final exactAlarmResult = await Permission.scheduleExactAlarm
              .request();
          if (!exactAlarmResult.isGranted) {
            debugPrint(
              'Exact alarm permission denied - will use inexact scheduling',
            );
          }
        }

        // Check battery optimization (important for XOS/ColorOS)
        final batteryOptimizationStatus =
            await Permission.ignoreBatteryOptimizations.status;
        if (batteryOptimizationStatus.isDenied) {
          debugPrint(
            'Requesting battery optimization exemption for reliable notifications',
          );
          await Permission.ignoreBatteryOptimizations.request();
        }

        // Log permissions status for debugging
        debugPrint('Notification permissions status:');
        debugPrint('- Notification: ${notificationStatus.name}');
        debugPrint('- Exact alarm: ${exactAlarmStatus.name}');
        debugPrint('- Battery optimization: ${batteryOptimizationStatus.name}');

        return allPermissionsGranted;
      }
      return true;
    } catch (e) {
      debugPrint('Error requesting notification permissions: $e');
      await ErrorLogger.instance.logPermissionError(
        permission: 'notification',
        status: 'request_failed',
        context: 'notification_permission_request',
      );
      return false;
    }
  }

  /// Jadwalkan notifikasi harian untuk waktu sholat
  static Future<void> scheduleDailyNotifications(
    PrayerTimes prayerTimes,
  ) async {
    try {
      // Cancel semua notifikasi yang ada
      await _notificationsPlugin.cancelAll();

      final prefs = await SharedPreferences.getInstance();
      final notificationsEnabled =
          prefs.getBool('prayer_notifications') ?? true;

      if (!notificationsEnabled) {
        debugPrint('Prayer notifications disabled');
        return;
      }

      // Cek pengaturan countdown
      final countdownEnabled = prefs.getBool('countdown_notifications') ?? true;

      // Jadwalkan notifikasi untuk waktu sholat wajib
      final prayerSchedule = [
        {'name': 'Subuh', 'time': prayerTimes.fajr, 'id': 1},
        {'name': 'Dzuhur', 'time': prayerTimes.dhuhr, 'id': 2},
        {'name': 'Ashar', 'time': prayerTimes.asr, 'id': 3},
        {'name': 'Maghrib', 'time': prayerTimes.maghrib, 'id': 4},
        {'name': 'Isya', 'time': prayerTimes.isha, 'id': 5},
      ];

      for (final prayer in prayerSchedule) {
        final prayerTime = prayer['time'] as DateTime;
        final prayerName = prayer['name'] as String;
        final notificationId = prayer['id'] as int;

        // Terapkan offset waktu dari pengaturan
        final adjustedTime = await _applyTimeOffset(prayerTime, prayerName);

        if (adjustedTime.isAfter(DateTime.now())) {
          // Jadwalkan countdown 10 menit sebelum (jika diaktifkan)
          if (countdownEnabled) {
            final countdownTime = adjustedTime.subtract(
              const Duration(minutes: 10),
            );
            if (countdownTime.isAfter(DateTime.now())) {
              await _scheduleCountdownNotification(
                countdownTime,
                prayerName,
                notificationId + 100,
              );
            }
          }

          // Jadwalkan notifikasi utama
          await _schedulePrayerNotification(
            adjustedTime,
            prayerName,
            notificationId,
          );
        }
      }

      debugPrint('Daily notifications scheduled successfully');

      // Start foreground service untuk additional monitoring (XOS/Infinix compatibility)
      await startForegroundService();
    } catch (e, stackTrace) {
      debugPrint('Error scheduling notifications: $e');
      await ErrorLogger.instance.logError(
        message: 'Failed to schedule notifications',
        error: e,
        stackTrace: stackTrace,
        context: 'notification_scheduling',
      );
    }
  }

  /// Jadwalkan notifikasi untuk waktu sholat dengan fallback scheduling yang lebih robust
  static Future<void> _schedulePrayerNotification(
    DateTime scheduledTime,
    String prayerName,
    int notificationId,
  ) async {
    const androidDetails = AndroidNotificationDetails(
      _prayerChannelId,
      'Notifikasi Sholat',
      channelDescription: 'Notifikasi untuk waktu sholat wajib',
      importance: Importance.max,
      priority: Priority.max,
      enableVibration: true,
      autoCancel: false,
      ongoing: false,
      showWhen: true,
      playSound: false, // Disable default sound karena kita pakai audio adzan
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
    );

    const notificationDetails = NotificationDetails(android: androidDetails);
    final tzScheduledTime = tz.TZDateTime.from(scheduledTime, tz.local);

    try {
      // Method 1: Try exact scheduling dengan flutter_local_notifications
      final exactAlarmStatus = await Permission.scheduleExactAlarm.status;

      if (exactAlarmStatus.isGranted) {
        await _notificationsPlugin.zonedSchedule(
          notificationId,
          'Waktu $prayerName',
          'Sudah masuk waktu sholat $prayerName',
          tzScheduledTime,
          notificationDetails,
          payload: 'prayer:$prayerName', // Tambah payload untuk trigger audio
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
        debugPrint('✓ Exact alarm scheduled for $prayerName at $scheduledTime');

        // Method 2: Juga set native AlarmManager sebagai backup (XOS/Infinix)
        await _setExactAlarmViaMethodChannel(
          scheduledTime,
          'Waktu $prayerName',
          'Sudah masuk waktu sholat $prayerName',
        );
      } else {
        // Fallback to inexact scheduling
        await _notificationsPlugin.zonedSchedule(
          notificationId,
          'Waktu $prayerName',
          'Sudah masuk waktu sholat $prayerName',
          tzScheduledTime,
          notificationDetails,
          payload: 'prayer:$prayerName', // Tambah payload untuk trigger audio
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
        debugPrint(
          '⚠ Inexact alarm scheduled for $prayerName at $scheduledTime (exact not permitted)',
        );
      }

      // Method 3: Set periodic check (foreground service approach)
      await _scheduleForegroundCheck(
        scheduledTime,
        prayerName,
        notificationId + 2000,
      );
    } catch (e) {
      debugPrint('Error scheduling prayer notification for $prayerName: $e');
      // Try one more time with basic scheduling
      try {
        await _notificationsPlugin.zonedSchedule(
          notificationId,
          'Waktu $prayerName',
          'Sudah masuk waktu sholat $prayerName',
          tzScheduledTime,
          notificationDetails,
          androidScheduleMode: AndroidScheduleMode.alarmClock,
        );
        debugPrint('✓ Basic scheduling fallback successful for $prayerName');
      } catch (fallbackError) {
        debugPrint(
          '❌ All scheduling methods failed for $prayerName: $fallbackError',
        );
        await ErrorLogger.instance.logError(
          message: 'Failed to schedule notification for $prayerName',
          error: fallbackError,
          stackTrace: StackTrace.current,
          context: 'prayer_notification_scheduling',
        );
      }
    }
  }

  /// Jadwalkan notifikasi countdown 10 menit sebelum sholat dengan fallback yang lebih robust
  static Future<void> _scheduleCountdownNotification(
    DateTime scheduledTime,
    String prayerName,
    int notificationId,
  ) async {
    const androidDetails = AndroidNotificationDetails(
      _countdownChannelId,
      'Countdown Sholat',
      channelDescription: 'Pengingat 10 menit sebelum waktu sholat',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
      category: AndroidNotificationCategory.reminder,
    );

    const notificationDetails = NotificationDetails(android: androidDetails);
    final tzScheduledTime = tz.TZDateTime.from(scheduledTime, tz.local);

    try {
      final exactAlarmStatus = await Permission.scheduleExactAlarm.status;

      if (exactAlarmStatus.isGranted) {
        await _notificationsPlugin.zonedSchedule(
          notificationId,
          'Persiapan Waktu $prayerName',
          '10 menit menuju waktu $prayerName',
          tzScheduledTime,
          notificationDetails,
          payload: 'countdown:$prayerName', // Payload untuk countdown
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
        debugPrint(
          '✓ Exact countdown scheduled for $prayerName at $scheduledTime',
        );

        // Also set native AlarmManager backup
        await _setExactAlarmViaMethodChannel(
          scheduledTime,
          'Persiapan Waktu $prayerName',
          '10 menit menuju waktu $prayerName',
        );
      } else {
        await _notificationsPlugin.zonedSchedule(
          notificationId,
          'Persiapan Waktu $prayerName',
          '10 menit menuju waktu $prayerName',
          tzScheduledTime,
          notificationDetails,
          payload: 'countdown:$prayerName', // Payload untuk countdown
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
        debugPrint(
          '⚠ Inexact countdown scheduled for $prayerName at $scheduledTime',
        );
      }

      // Set foreground service check untuk countdown juga
      await _scheduleForegroundCheck(
        scheduledTime,
        prayerName,
        notificationId + 3000,
        isCountdown: true,
      );
    } catch (e) {
      debugPrint('Error scheduling countdown notification for $prayerName: $e');
      await ErrorLogger.instance.logError(
        message: 'Failed to schedule countdown for $prayerName',
        error: e,
        stackTrace: StackTrace.current,
        context: 'countdown_notification_scheduling',
      );
    }
  }

  /// Terapkan offset waktu dari pengaturan user
  static Future<DateTime> _applyTimeOffset(
    DateTime originalTime,
    String prayerName,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final offsetKey = '${prayerName.toLowerCase()}_offset';
    final offsetMinutes = prefs.getInt(offsetKey) ?? 0;

    return originalTime.add(Duration(minutes: offsetMinutes));
  }

  /// Get time offset for specific prayer
  static Future<int> getTimeOffset(String prayerName) async {
    final prefs = await SharedPreferences.getInstance();
    final offsetKey = '${prayerName.toLowerCase()}_offset';
    return prefs.getInt(offsetKey) ?? 0;
  }

  /// Save time offset for specific prayer
  static Future<void> saveTimeOffset(
    String prayerName,
    int offsetMinutes,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final offsetKey = '${prayerName.toLowerCase()}_offset';
    await prefs.setInt(offsetKey, offsetMinutes);
  }

  /// Get day offset
  static Future<int> getDayOffset() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('day_offset') ?? 0;
  }

  /// Save day offset
  static Future<void> saveDayOffset(int offsetDays) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('day_offset', offsetDays);
  }

  /// Cancel semua notifikasi
  static Future<void> cancelAllNotifications() async {
    try {
      await _notificationsPlugin.cancelAll();
      debugPrint('All notifications cancelled');
    } catch (e, stackTrace) {
      debugPrint('Error cancelling notifications: $e');
      await ErrorLogger.instance.logError(
        message: 'Failed to cancel notifications',
        error: e,
        stackTrace: stackTrace,
        context: 'notification_cancellation',
      );
    }
  }

  /// Tampilkan notifikasi instant untuk testing
  static Future<void> showTestNotification() async {
    try {
      const androidDetails = AndroidNotificationDetails(
        _prayerChannelId,
        'Test Notification',
        channelDescription: 'Notifikasi test untuk memastikan sistem berfungsi',
        importance: Importance.high,
        priority: Priority.high,
        enableVibration: true,
        autoCancel: true,
      );

      const notificationDetails = NotificationDetails(android: androidDetails);

      await _notificationsPlugin.show(
        999,
        'Test Notifikasi',
        'Sistem notifikasi berfungsi dengan baik! ${DateTime.now().toString().substring(11, 19)}',
        notificationDetails,
        payload: 'test:notification', // Payload untuk test
      );

      debugPrint('✓ Test notification sent successfully');
    } catch (e, stackTrace) {
      debugPrint('❌ Error showing test notification: $e');
      await ErrorLogger.instance.logError(
        message: 'Failed to show test notification',
        error: e,
        stackTrace: stackTrace,
        context: 'test_notification',
      );
    }
  }

  /// Test scheduled notification (akan muncul dalam 10 detik)
  static Future<void> showScheduledTestNotification() async {
    try {
      final scheduledTime = DateTime.now().add(const Duration(seconds: 10));

      debugPrint(
        'Scheduling test notification for: ${scheduledTime.toString()}',
      );
      debugPrint('Current time: ${DateTime.now().toString()}');

      const androidDetails = AndroidNotificationDetails(
        _prayerChannelId,
        'Scheduled Test',
        channelDescription: 'Test notifikasi terjadwal',
        importance: Importance.high,
        priority: Priority.high,
        enableVibration: true,
        playSound: true,
        autoCancel: true,
      );

      const notificationDetails = NotificationDetails(android: androidDetails);

      // Try different scheduling approaches
      final exactAlarmStatus = await Permission.scheduleExactAlarm.status;

      debugPrint('Exact alarm permission status: ${exactAlarmStatus.name}');

      try {
        // First try with basic show() method with delayed execution
        Timer(const Duration(seconds: 10), () async {
          await _notificationsPlugin.show(
            997,
            'Test Timer (Direct)',
            'Notifikasi test berhasil! Timer method.',
            notificationDetails,
          );
          debugPrint('✓ Timer-based notification executed');
        });

        // Also try scheduled notification
        if (exactAlarmStatus.isGranted) {
          await _notificationsPlugin.zonedSchedule(
            998,
            'Test Terjadwal (Exact)',
            'Notifikasi terjadwal berhasil! Exact alarm mode.',
            tz.TZDateTime.from(scheduledTime, tz.local),
            notificationDetails,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          );
          debugPrint(
            '✓ Scheduled test notification (exact) for ${scheduledTime.toString().substring(11, 19)}',
          );

          // Also try AlarmManager approach for XOS/Infinix compatibility
          await _setExactAlarmViaMethodChannel(
            scheduledTime,
            'Test AlarmManager',
            'Notifikasi via AlarmManager untuk XOS/Infinix',
          );
        } else {
          await _notificationsPlugin.zonedSchedule(
            998,
            'Test Terjadwal (Inexact)',
            'Notifikasi terjadwal berhasil! Inexact alarm mode.',
            tz.TZDateTime.from(scheduledTime, tz.local),
            notificationDetails,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
          debugPrint(
            '⚠ Scheduled test notification (inexact) for ${scheduledTime.toString().substring(11, 19)}',
          );
        }
      } catch (scheduleError) {
        debugPrint('❌ Scheduling failed: $scheduleError');

        // Fallback: try simple show() after delay
        Timer(const Duration(seconds: 5), () async {
          try {
            await _notificationsPlugin.show(
              996,
              'Test Fallback',
              'Fallback notification test - ${DateTime.now().toString().substring(11, 19)}',
              notificationDetails,
            );
            debugPrint('✓ Fallback notification executed');
          } catch (fallbackError) {
            debugPrint('❌ Fallback also failed: $fallbackError');
          }
        });
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error scheduling test notification: $e');
      await ErrorLogger.instance.logError(
        message: 'Failed to schedule test notification',
        error: e,
        stackTrace: stackTrace,
        context: 'scheduled_test_notification',
      );
    }
  }

  /// Debug info untuk troubleshooting notifikasi
  static Future<void> printNotificationDebugInfo() async {
    try {
      debugPrint('=== NOTIFICATION DEBUG INFO ===');

      // Check permissions
      final notificationStatus = await Permission.notification.status;
      final exactAlarmStatus = await Permission.scheduleExactAlarm.status;
      final batteryOptStatus =
          await Permission.ignoreBatteryOptimizations.status;

      debugPrint('Permissions:');
      debugPrint('- Notification: ${notificationStatus.name}');
      debugPrint('- Exact Alarm: ${exactAlarmStatus.name}');
      debugPrint('- Battery Optimization: ${batteryOptStatus.name}');

      // Check pending notifications
      final pendingNotifications = await _notificationsPlugin
          .pendingNotificationRequests();
      debugPrint('Pending notifications: ${pendingNotifications.length}');

      for (final notification in pendingNotifications) {
        debugPrint('- ID: ${notification.id}, Title: ${notification.title}');
      }

      // Check active notifications
      final activeNotifications = await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.getActiveNotifications();

      debugPrint('Active notifications: ${activeNotifications?.length ?? 0}');

      debugPrint('=== END DEBUG INFO ===');
    } catch (e) {
      debugPrint('Error getting debug info: $e');
    }
  }

  /// Cek apakah notifikasi diizinkan
  static Future<bool> areNotificationsEnabled() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final status = await Permission.notification.status;
        return status.isGranted;
      }
      return true;
    } catch (e) {
      debugPrint('Error checking notification permissions: $e');
      return false;
    }
  }

  /// Putar audio adzan berdasarkan waktu sholat
  static Future<void> playAdhanAudio(String prayerName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isAudioEnabled = prefs.getBool('adhan_audio_enabled') ?? true;

      if (!isAudioEnabled) {
        debugPrint('Audio adzan disabled in settings');
        return;
      }

      String audioPath;
      if (prayerName.toLowerCase() == 'subuh') {
        audioPath = 'assets/audios/adzan_subuh.mp3';
      } else {
        audioPath = 'assets/audios/adzan.mp3';
      }

      await _audioPlayer.stop(); // Stop any current audio
      await _audioPlayer.play(
        AssetSource(audioPath.replaceFirst('assets/', '')),
      );

      debugPrint('✓ Playing adhan audio for $prayerName: $audioPath');
    } catch (e) {
      debugPrint('❌ Error playing adhan audio: $e');
      await ErrorLogger.instance.logError(
        message: 'Failed to play adhan audio for $prayerName',
        error: e,
        stackTrace: StackTrace.current,
        context: 'adhan_audio_playback',
      );
    }
  }

  /// Stop audio adzan yang sedang diputar
  static Future<void> stopAdhanAudio() async {
    try {
      await _audioPlayer.stop();
      debugPrint('✓ Adhan audio stopped');
    } catch (e) {
      debugPrint('❌ Error stopping adhan audio: $e');
    }
  }

  /// Dispose semua resources
  static void dispose() {
    _countdownTimer?.cancel();
    _audioPlayer.dispose();
  }

  /// Method untuk menggunakan AlarmManager via method channel (XOS/Infinix compatibility)
  static Future<void> _setExactAlarmViaMethodChannel(
    DateTime scheduledTime,
    String title,
    String body,
  ) async {
    try {
      await _alarmChannel.invokeMethod('setExactAlarm', {
        'time': scheduledTime.millisecondsSinceEpoch,
        'title': title,
        'body': body,
        'notificationId': 995,
      });
      debugPrint(
        '✓ AlarmManager exact alarm set via method channel for XOS/Infinix',
      );
    } catch (e) {
      debugPrint('❌ AlarmManager method channel failed: $e');
    }
  }

  /// Start foreground service untuk monitoring prayer times
  static Future<void> startForegroundService() async {
    try {
      await _alarmChannel.invokeMethod('startForegroundService');
      debugPrint('✓ Foreground service started');
    } catch (e) {
      debugPrint('❌ Failed to start foreground service: $e');
    }
  }

  /// Stop foreground service
  static Future<void> stopForegroundService() async {
    try {
      await _alarmChannel.invokeMethod('stopForegroundService');
      debugPrint('✓ Foreground service stopped');
    } catch (e) {
      debugPrint('❌ Failed to stop foreground service: $e');
    }
  }

  /// Foreground service approach untuk memastikan notifikasi muncul
  static Future<void> _scheduleForegroundCheck(
    DateTime scheduledTime,
    String prayerName,
    int notificationId, {
    bool isCountdown = false,
  }) async {
    try {
      // Hitung waktu untuk melakukan check (5 menit sebelum waktu target)
      final checkTime = scheduledTime.subtract(const Duration(minutes: 5));
      final now = DateTime.now();

      // Jika waktu check sudah lewat, set check 30 detik dari sekarang
      final actualCheckTime = checkTime.isBefore(now)
          ? now.add(const Duration(seconds: 30))
          : checkTime;

      // Set timer untuk melakukan pengecekan
      final delay = actualCheckTime.difference(now);
      if (delay.inSeconds > 0) {
        Timer(delay, () async {
          await _performForegroundCheck(
            scheduledTime,
            prayerName,
            notificationId,
            isCountdown,
          );
        });

        debugPrint(
          '✓ Foreground check scheduled for $prayerName ${isCountdown ? "(countdown)" : ""} at $actualCheckTime',
        );
      }
    } catch (e) {
      debugPrint('❌ Error scheduling foreground check: $e');
    }
  }

  /// Perform actual foreground check
  static Future<void> _performForegroundCheck(
    DateTime targetTime,
    String prayerName,
    int notificationId,
    bool isCountdown,
  ) async {
    try {
      final now = DateTime.now();
      final timeUntilTarget = targetTime.difference(now);

      // Jika waktu target sudah dekat (dalam 1 menit), tunggu dan trigger notifikasi
      if (timeUntilTarget.inMinutes <= 1 && timeUntilTarget.inSeconds > 0) {
        Timer(timeUntilTarget, () async {
          final title = isCountdown
              ? 'Persiapan Waktu $prayerName'
              : 'Waktu $prayerName';
          final body = isCountdown
              ? '10 menit menuju waktu $prayerName'
              : 'Sudah masuk waktu sholat $prayerName';

          await _notificationsPlugin.show(
            notificationId,
            title,
            body,
            NotificationDetails(
              android: AndroidNotificationDetails(
                isCountdown ? _countdownChannelId : _prayerChannelId,
                isCountdown ? 'Countdown Sholat' : 'Notifikasi Sholat',
                importance: isCountdown ? Importance.high : Importance.max,
                priority: isCountdown ? Priority.high : Priority.max,
                enableVibration: true,
                playSound:
                    !isCountdown, // Only play sound for prayer, not countdown
                category: isCountdown
                    ? AndroidNotificationCategory.reminder
                    : AndroidNotificationCategory.alarm,
              ),
            ),
            payload: isCountdown
                ? 'countdown:$prayerName'
                : 'prayer:$prayerName',
          );

          debugPrint(
            '✓ Foreground notification triggered for $prayerName ${isCountdown ? "(countdown)" : ""}',
          );
        });
      }
    } catch (e) {
      debugPrint('❌ Error in foreground check: $e');
    }
  }

  /// Set volume untuk audio adzan
  static Future<void> setAdhanVolume(double volume) async {
    await _audioPlayer.setVolume(volume);
  }

  /// Get status apakah audio adzan sedang diputar
  static Future<bool> isAdhanPlaying() async {
    return _audioPlayer.state == PlayerState.playing;
  }

  /// Get duration audio adzan yang sedang diputar
  static Future<Duration?> getAdhanDuration() async {
    return _audioPlayer.getDuration();
  }

  /// Get current position audio adzan
  static Stream<Duration> getAdhanPosition() {
    return _audioPlayer.onPositionChanged;
  }
}
