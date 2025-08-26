import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:adhan/adhan.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Channel notifikasi yang disederhanakan
  static const String _prayerChannelId = 'prayer_channel';
  static const String _countdownChannelId = 'countdown_channel';

  // ID notifikasi countdown yang persistent
  static const int _countdownNotificationId = 1000;

  // Timer untuk countdown
  static Timer? _countdownTimer;

  /// Inisialisasi plugin notifikasi
  static Future<bool> initialize() async {
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings darwinInit =
        DarwinInitializationSettings();

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: androidInit,
          iOS: darwinInit,
          macOS: darwinInit,
        );

    await _notificationsPlugin.initialize(initializationSettings);

    final permissionGranted = await _requestNotificationPermission();
    if (!permissionGranted) {
      debugPrint('Notification permissions not granted');
      return false;
    }

    await _createNotificationChannels();
    return true;
  }

  /// Meminta izin notifikasi
  static Future<bool> _requestNotificationPermission() async {
    final status = await Permission.notification.request();
    if (status.isDenied) {
      debugPrint('Notification permission denied');
      return false;
    }

    if (await Permission.scheduleExactAlarm.isDenied) {
      await Permission.scheduleExactAlarm.request();
    }

    return status.isGranted;
  }

  /// Membuat channel notifikasi
  static Future<void> _createNotificationChannels() async {
    const AndroidNotificationChannel prayerChannel = AndroidNotificationChannel(
      _prayerChannelId,
      'Notifikasi Azan',
      description: 'Channel untuk notifikasi waktu sholat dengan suara azan.',
      importance: Importance.max,
      enableVibration: true,
      showBadge: true,
      playSound: true,
    );

    const AndroidNotificationChannel countdownChannel =
        AndroidNotificationChannel(
          _countdownChannelId,
          'Countdown Sholat',
          description: 'Channel untuk countdown 10 menit sebelum waktu sholat.',
          importance: Importance.low,
          enableVibration: false,
          showBadge: false,
          playSound: false,
          sound: RawResourceAndroidNotificationSound('notification'),
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
  }

  /// Jadwalkan notifikasi harian untuk semua waktu sholat
  static Future<void> scheduleDailyNotifications(
    PrayerTimes prayerTimes,
  ) async {
    await _notificationsPlugin.cancelAll();

    final prefs = await SharedPreferences.getInstance();
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
              notificationId + 100, // Offset ID untuk countdown
            );
          }
        }

        // Jadwalkan notifikasi azan utama
        await _schedulePrayerNotification(
          adjustedTime,
          prayerName,
          notificationId,
        );
      }
    }

    // Mulai countdown aktif jika diaktifkan
    if (countdownEnabled) {
      _startActiveCountdown(prayerTimes);
    }
  }

  /// Terapkan offset waktu berdasarkan pengaturan per waktu sholat
  static Future<DateTime> _applyTimeOffset(
    DateTime originalTime,
    String prayerName,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final offsetKey = 'time_offset_${prayerName.toLowerCase()}';
    final offset = prefs.getInt(offsetKey) ?? 0;
    return originalTime.add(Duration(minutes: offset));
  }

  /// Jadwalkan notifikasi countdown
  static Future<void> _scheduleCountdownNotification(
    DateTime scheduledTime,
    String prayerName,
    int notificationId,
  ) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          _countdownChannelId,
          'Countdown Sholat',
          channelDescription: 'Pengingat 10 menit sebelum waktu sholat',
          importance: Importance.low,
          priority: Priority.low,
          sound: RawResourceAndroidNotificationSound('notification'),
          enableVibration: false,
        );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await _notificationsPlugin.zonedSchedule(
      notificationId,
      'Persiapan Waktu $prayerName',
      '10 menit menuju waktu $prayerName',
      tz.TZDateTime.from(scheduledTime, tz.local),
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  /// Jadwalkan notifikasi azan utama
  static Future<void> _schedulePrayerNotification(
    DateTime scheduledTime,
    String prayerName,
    int notificationId,
  ) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          _prayerChannelId,
          'Notifikasi Azan',
          channelDescription: 'Notifikasi waktu sholat dengan suara azan',
          importance: Importance.max,
          priority: Priority.high,
          enableVibration: true,
          playSound: true,
        );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await _notificationsPlugin.zonedSchedule(
      notificationId,
      'Waktu $prayerName',
      'Telah tiba waktu sholat $prayerName',
      tz.TZDateTime.from(scheduledTime, tz.local),
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  /// Mulai countdown aktif yang terus berjalan
  static void _startActiveCountdown(PrayerTimes prayerTimes) async {
    _countdownTimer?.cancel();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final now = DateTime.now();
      DateTime? nextPrayerTime;
      String nextPrayerName = '';

      // Tentukan waktu sholat berikutnya
      if (now.isBefore(prayerTimes.fajr)) {
        nextPrayerTime = prayerTimes.fajr;
        nextPrayerName = 'Subuh';
      } else if (now.isBefore(prayerTimes.dhuhr)) {
        nextPrayerTime = prayerTimes.dhuhr;
        nextPrayerName = 'Dzuhur';
      } else if (now.isBefore(prayerTimes.asr)) {
        nextPrayerTime = prayerTimes.asr;
        nextPrayerName = 'Ashar';
      } else if (now.isBefore(prayerTimes.maghrib)) {
        nextPrayerTime = prayerTimes.maghrib;
        nextPrayerName = 'Maghrib';
      } else if (now.isBefore(prayerTimes.isha)) {
        nextPrayerTime = prayerTimes.isha;
        nextPrayerName = 'Isya';
      }

      if (nextPrayerTime != null) {
        final adjustedTime = await _applyTimeOffset(
          nextPrayerTime,
          nextPrayerName,
        );
        final difference = adjustedTime.difference(now);

        // Jika dalam 10 menit, tampilkan countdown di notifikasi
        if (difference.inMinutes <= 10 && difference.inMinutes >= 0) {
          final minutes = difference.inMinutes;
          final seconds = difference.inSeconds.remainder(60);

          await _showActiveCountdownNotification(
            nextPrayerName,
            minutes,
            seconds,
          );
        } else {
          // Hapus notifikasi countdown jika sudah lewat 10 menit
          await _notificationsPlugin.cancel(_countdownNotificationId);
        }
      }
    });
  }

  /// Tampilkan notifikasi countdown aktif
  static Future<void> _showActiveCountdownNotification(
    String prayerName,
    int minutes,
    int seconds,
  ) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          _countdownChannelId,
          'Countdown Sholat',
          channelDescription: 'Hitungan mundur waktu sholat',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          enableVibration: false,
          playSound: false,
        );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    final timeText =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    await _notificationsPlugin.show(
      _countdownNotificationId,
      'Menuju Waktu $prayerName',
      'Sisa waktu: $timeText',
      notificationDetails,
    );
  }

  /// Hentikan semua timer dan notifikasi
  static void stopCountdown() {
    _countdownTimer?.cancel();
    _notificationsPlugin.cancel(_countdownNotificationId);
  }

  /// Simpan offset waktu untuk waktu sholat tertentu
  static Future<void> saveTimeOffset(
    String prayerName,
    int offsetMinutes,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final offsetKey = 'time_offset_${prayerName.toLowerCase()}';
    await prefs.setInt(offsetKey, offsetMinutes);
  }

  /// Ambil offset waktu untuk waktu sholat tertentu
  static Future<int> getTimeOffset(String prayerName) async {
    final prefs = await SharedPreferences.getInstance();
    final offsetKey = 'time_offset_${prayerName.toLowerCase()}';
    return prefs.getInt(offsetKey) ?? 0;
  }

  /// Simpan offset hari
  static Future<void> saveDayOffset(int offsetDays) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('day_offset', offsetDays);
  }

  /// Ambil offset hari
  static Future<int> getDayOffset() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('day_offset') ?? 0;
  }

  /// Fungsi kompatibilitas untuk kode lama - hapus fitur yang tidak perlu
  static Future<void> testNotification() async {
    // Hapus fitur test notification sesuai permintaan
    debugPrint('Test notification feature has been removed');
  }

  static Future<void> testNotificationWithAudio(String audioPath) async {
    // Hapus fitur test notification sesuai permintaan
    debugPrint('Test notification with audio feature has been removed');
  }
}
