import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:adhan/adhan.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';
import 'package:jadwal_sholat_app/services/error_logger.dart';
import 'package:jadwal_sholat_app/services/audio_permission_service.dart';

class NotificationServiceEnhanced {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Platform channel for audio playback via native ringtone/notification stream
  static const MethodChannel _audioChannel = MethodChannel(
    'jadwalsholat.rasyid/audio',
  );

  // Audio player untuk adzan
  static final AudioPlayer _audioPlayer = AudioPlayer();

  // Channel notifikasi
  static const String _prayerChannelId = 'prayer_enhanced_channel';
  static const String _countdownChannelId = 'countdown_enhanced_channel';
  static const String _imsakChannelId = 'imsak_channel';
  static const String _foregroundChannelId = 'foreground_service_channel';

  // Timer untuk countdown live
  static Timer? _countdownTimer;
  static Timer? _dailyRefreshTimer;

  // Status countdown
  static String? _currentCountdownPrayer;
  static DateTime? _nextPrayerTime;
  static bool _isCountdownActive = false;

  // Notification IDs untuk manajemen yang lebih baik
  static const int _baseNotificationId = 1000;
  static const int _countdownNotificationId = 2000;
  static const int _imsakNotificationId = 3000;
  static const int _foregroundServiceId = 4000;

  /// Inisialisasi plugin notifikasi dengan konfigurasi enhanced
  static Future<bool> initialize() async {
    try {
      // Inisialisasi pengaturan Android dengan custom sound
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

      // Buat channel notifikasi enhanced
      await _createEnhancedNotificationChannels();

      // Setup daily refresh timer
      await _setupDailyRefreshTimer();

      debugPrint('NotificationServiceEnhanced initialized');
      return true;
    } catch (e, stackTrace) {
      debugPrint('Error initializing enhanced notifications: $e');
      await ErrorLogger.instance.logError(
        message: 'Failed to initialize enhanced notifications',
        error: e,
        stackTrace: stackTrace,
        context: 'notification_enhanced_initialization',
      );
      return false;
    }
  }

  /// Setup timer untuk refresh harian (setiap 24 jam)
  static Future<void> _setupDailyRefreshTimer() async {
    _dailyRefreshTimer?.cancel();

    // Refresh setiap 24 jam untuk memastikan notifikasi tetap berjalan
    _dailyRefreshTimer = Timer.periodic(const Duration(hours: 24), (
      timer,
    ) async {
      debugPrint('Daily notification refresh triggered');
      await refreshDailyNotifications();
    });
  }

  /// Refresh notifikasi harian
  static Future<void> refreshDailyNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notificationsEnabled =
          prefs.getBool('prayer_notifications') ?? true;

      if (!notificationsEnabled) {
        debugPrint('Prayer notifications disabled, skipping refresh');
        return;
      }

      // Ambil koordinat terakhir yang disimpan
      final latitude = prefs.getDouble('last_latitude');
      final longitude = prefs.getDouble('last_longitude');

      if (latitude != null && longitude != null) {
        // Hitung ulang waktu sholat untuk hari ini dan besok
        final coordinates = Coordinates(latitude, longitude);
        final params = CalculationMethod.muslim_world_league.getParameters();
        params.madhab = Madhab.shafi;

        // Waktu sholat hari ini
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

        // Waktu sholat besok
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

        // Jadwalkan ulang semua notifikasi
        await scheduleEnhancedDailyNotifications(todayPrayerTimes);
        await scheduleEnhancedDailyNotifications(tomorrowPrayerTimes);

        debugPrint('Daily notifications refreshed successfully');
      }
    } catch (e) {
      debugPrint('Error refreshing daily notifications: $e');
    }
  }

  /// Callback saat notifikasi ditekan dengan handling enhanced
  static void _onNotificationTapped(NotificationResponse response) {
    debugPrint('Enhanced notification tapped: ${response.payload}');

    if (response.payload != null) {
      if (response.payload!.contains('prayer:')) {
        // Notifikasi waktu sholat - play audio adzan penuh
        final prayerName = response.payload!.split(':')[1];
        playFullAdhanAudio(prayerName);
      } else if (response.payload!.contains('countdown:')) {
        // Notifikasi countdown - show info
        final prayerName = response.payload!.split(':')[1];
        debugPrint('Countdown notification for $prayerName tapped');
      } else if (response.payload!.contains('imsak:')) {
        // Notifikasi imsak - play short notification sound
        debugPrint('Imsak notification tapped');
        playShortNotificationSound();
      } else if (response.payload!.contains('test:')) {
        // Test notification
        debugPrint('Test notification tapped - playing test audio');
        playFullAdhanAudio('Dzuhur');
      }
    }
  }

  /// Membuat channel notifikasi enhanced
  static Future<void> _createEnhancedNotificationChannels() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final useNative = prefs.getBool('use_native_ringtone_playback') ?? true;
      // Channel untuk notifikasi utama waktu sholat dengan priority tinggi
      final prayerChannel = AndroidNotificationChannel(
        _prayerChannelId,
        'Notifikasi Sholat Enhanced',
        description: 'Notifikasi untuk waktu sholat dengan audio adzan penuh.',
        importance: Importance.max,
        enableVibration: true,
        showBadge: true,
        playSound: useNative,
        enableLights: true,
      );

      // Channel untuk countdown live dengan update berkala
      final countdownChannel = AndroidNotificationChannel(
        _countdownChannelId,
        'Countdown Sholat Live',
        description: 'Countdown live menjelang waktu sholat.',
        importance: Importance.low,
        enableVibration: false,
        showBadge: false,
        playSound: false,
      );

      // Channel untuk notifikasi imsak
      final imsakChannel = AndroidNotificationChannel(
        _imsakChannelId,
        'Notifikasi Imsak',
        description: 'Notifikasi untuk waktu imsak (mulai puasa).',
        importance: Importance.high,
        enableVibration: true,
        showBadge: true,
        playSound: useNative,
      );

      // Channel untuk foreground service
      final foregroundChannel = AndroidNotificationChannel(
        _foregroundChannelId,
        'Layanan Latar Belakang Sholat',
        description: 'Layanan untuk menjaga notifikasi sholat tetap berjalan.',
        importance: Importance.low,
        enableVibration: false,
        showBadge: false,
        playSound: false,
      );

      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      // If using native sounds, register channel sounds with RawResourceAndroidNotificationSound
      if (useNative) {
        await androidPlugin?.createNotificationChannel(prayerChannel);
        await androidPlugin?.createNotificationChannel(countdownChannel);
        await androidPlugin?.createNotificationChannel(imsakChannel);
        await androidPlugin?.createNotificationChannel(foregroundChannel);
      } else {
        await androidPlugin?.createNotificationChannel(prayerChannel);
        await androidPlugin?.createNotificationChannel(countdownChannel);
        await androidPlugin?.createNotificationChannel(imsakChannel);
        await androidPlugin?.createNotificationChannel(foregroundChannel);
      }

      debugPrint('Enhanced notification channels created');
    } catch (e, stackTrace) {
      debugPrint('Error creating enhanced notification channels: $e');
      await ErrorLogger.instance.logError(
        message: 'Failed to create enhanced notification channels',
        error: e,
        stackTrace: stackTrace,
        context: 'notification_enhanced_channel_creation',
      );
    }
  }

  /// Cek dan minta permission dengan handling enhanced
  static Future<bool> requestEnhancedPermissions() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        bool allPermissionsGranted = true;

        // Request notification permission (Android 13+)
        final notificationStatus = await Permission.notification.request();
        if (!notificationStatus.isGranted) {
          debugPrint('Notification permission denied');
          allPermissionsGranted = false;
        }

        // Request exact alarm permission (Android 12+) - Critical untuk akurasi
        final exactAlarmStatus = await Permission.scheduleExactAlarm.status;
        if (exactAlarmStatus.isDenied) {
          final exactAlarmResult = await Permission.scheduleExactAlarm
              .request();
          if (!exactAlarmResult.isGranted) {
            debugPrint(
              'Exact alarm permission denied - notifications may be inaccurate',
            );
            allPermissionsGranted = false;
          }
        }

        // Request battery optimization exemption - Critical untuk foreground service
        final batteryOptimizationStatus =
            await Permission.ignoreBatteryOptimizations.status;
        if (batteryOptimizationStatus.isDenied) {
          debugPrint('Requesting battery optimization exemption');
          await Permission.ignoreBatteryOptimizations.request();
        }

        // Request audio permission untuk full adzan playback
        final audioStatus = await Permission.audio.status;
        if (audioStatus.isDenied) {
          await Permission.audio.request();
        }

        // Log enhanced permissions status
        debugPrint('Enhanced notification permissions status:');
        debugPrint('- Notification: ${notificationStatus.name}');
        debugPrint('- Exact alarm: ${exactAlarmStatus.name}');
        debugPrint('- Battery optimization: ${batteryOptimizationStatus.name}');
        debugPrint('- Audio: ${audioStatus.name}');

        return allPermissionsGranted;
      }
      return true;
    } catch (e) {
      debugPrint('Error requesting enhanced notification permissions: $e');
      return false;
    }
  }

  /// Jadwalkan notifikasi enhanced dengan semua fitur
  static Future<void> scheduleEnhancedDailyNotifications(
    PrayerTimes prayerTimes,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notificationsEnabled =
          prefs.getBool('prayer_notifications') ?? true;
      final countdownEnabled = prefs.getBool('countdown_notifications') ?? true;
      final imsakEnabled = prefs.getBool('imsak_notifications') ?? true;

      if (!notificationsEnabled) {
        debugPrint('Prayer notifications disabled');
        return;
      }

      final now = DateTime.now();
      final prayerTimesMap = {
        'Subuh': prayerTimes.fajr,
        'Dzuhur': prayerTimes.dhuhr,
        'Ashar': prayerTimes.asr,
        'Maghrib': prayerTimes.maghrib,
        'Isya': prayerTimes.isha,
      };

      // Jadwalkan notifikasi imsak (10 menit sebelum Subuh)
      if (imsakEnabled && prayerTimes.fajr.isAfter(now)) {
        final imsakTime = prayerTimes.fajr.subtract(
          const Duration(minutes: 10),
        );
        if (imsakTime.isAfter(now)) {
          await _scheduleImsakNotification(imsakTime);
        }
      }

      // Simpan waktu sholat untuk referensi background service
      await _savePrayerTimesToPrefs(prayerTimesMap);

      // Jadwalkan notifikasi waktu sholat dan countdown
      for (final entry in prayerTimesMap.entries) {
        final prayerName = entry.key;
        final prayerTime = entry.value;

        if (prayerTime.isAfter(now)) {
          // Notifikasi waktu sholat
          await _schedulePrayerNotification(prayerName, prayerTime);

          // Countdown 10 menit sebelumnya
          if (countdownEnabled) {
            final countdownTime = prayerTime.subtract(
              const Duration(minutes: 10),
            );
            if (countdownTime.isAfter(now)) {
              await _scheduleCountdownStart(
                prayerName,
                countdownTime,
                prayerTime,
              );
            }
          }
        }
      }

      // Simpan waktu scheduling terakhir
      await prefs.setInt(
        'last_notification_schedule',
        now.millisecondsSinceEpoch,
      );

      debugPrint(
        'Enhanced daily notifications scheduled for ${prayerTimesMap.length} prayers',
      );
    } catch (e, stackTrace) {
      debugPrint('Error scheduling enhanced daily notifications: $e');
      await ErrorLogger.instance.logError(
        message: 'Failed to schedule enhanced daily notifications',
        error: e,
        stackTrace: stackTrace,
        context: 'enhanced_notification_scheduling',
      );
    }
  }

  /// Simpan waktu sholat ke SharedPreferences untuk background service
  static Future<void> _savePrayerTimesToPrefs(
    Map<String, DateTime> prayerTimes,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      for (final entry in prayerTimes.entries) {
        final prayerName = entry.key;
        final prayerTime = entry.value;
        final key = 'prayer_time_${prayerName.toLowerCase()}';

        await prefs.setString(key, prayerTime.toIso8601String());
        debugPrint('Saved prayer time for $prayerName: $prayerTime');
      }

      // Reset flag audio played untuk hari ini
      final now = DateTime.now();
      final prayers = ['subuh', 'dzuhur', 'ashar', 'maghrib', 'isya'];

      for (final prayer in prayers) {
        final audioPlayedKey =
            'audio_played_${prayer}_${now.year}_${now.month}_${now.day}';
        await prefs.setBool(audioPlayedKey, false);
      }

      debugPrint(
        'Prayer times saved to preferences for auto-play functionality',
      );
    } catch (e) {
      debugPrint('Error saving prayer times to preferences: $e');
    }
  }

  /// Jadwalkan notifikasi imsak
  static Future<void> _scheduleImsakNotification(DateTime imsakTime) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final useNative = prefs.getBool('use_native_ringtone_playback') ?? true;
      final scheduledDate = tz.TZDateTime.from(imsakTime, tz.local);
      final androidDetails = AndroidNotificationDetails(
        _imsakChannelId,
        'Notifikasi Imsak',
        channelDescription: 'Notifikasi untuk waktu imsak.',
        importance: Importance.high,
        enableVibration: true,
        playSound: useNative,
        icon: '@mipmap/ic_launcher',
        sound: useNative ? RawResourceAndroidNotificationSound('adzan') : null,
      );

      await _notificationsPlugin.zonedSchedule(
        _imsakNotificationId,
        'Waktu Imsak',
        'Mulai waktu imsak. Saatnya menahan diri dari makan dan minum.',
        scheduledDate,
        NotificationDetails(android: androidDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'imsak:notification',
      );

      debugPrint('Imsak notification scheduled for: $imsakTime');
    } catch (e) {
      debugPrint('Error scheduling imsak notification: $e');
    }
  }

  /// Jadwalkan notifikasi waktu sholat
  static Future<void> _schedulePrayerNotification(
    String prayerName,
    DateTime prayerTime,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final useNative = prefs.getBool('use_native_ringtone_playback') ?? true;
      final notificationId = _baseNotificationId + _getPrayerIndex(prayerName);
      final scheduledDate = tz.TZDateTime.from(prayerTime, tz.local);

      // Jadwalkan alarm untuk auto play audio
      await _scheduleAutoPlayAlarm(prayerName, prayerTime);

      final androidDetails = AndroidNotificationDetails(
        _prayerChannelId,
        'Notifikasi Sholat Enhanced',
        channelDescription: 'Notifikasi untuk waktu sholat.',
        importance: Importance.max,
        enableVibration: true,
        playSound: useNative,
        icon: '@mipmap/ic_launcher',
        enableLights: true,
        ledColor: const Color(0xFF4DB6AC),
        ledOnMs: 1000,
        ledOffMs: 500,
        autoCancel: false,
        ongoing: true,
        timeoutAfter: 300000,
        sound: useNative ? RawResourceAndroidNotificationSound('adzan') : null,
      );

      await _notificationsPlugin.zonedSchedule(
        notificationId,
        'Waktu $prayerName',
        'Telah masuk waktu sholat $prayerName. Audio azan sedang diputar.',
        scheduledDate,
        NotificationDetails(android: androidDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'prayer:$prayerName',
      );

      debugPrint(
        'Prayer notification scheduled for $prayerName at: $prayerTime',
      );
    } catch (e) {
      debugPrint('Error scheduling prayer notification for $prayerName: $e');
    }
  }

  /// Jadwalkan countdown start
  static Future<void> _scheduleCountdownStart(
    String prayerName,
    DateTime countdownStartTime,
    DateTime prayerTime,
  ) async {
    try {
      final notificationId =
          _countdownNotificationId + _getPrayerIndex(prayerName);
      final scheduledDate = tz.TZDateTime.from(countdownStartTime, tz.local);

      // Jadwalkan notifikasi untuk memulai countdown
      await _notificationsPlugin.zonedSchedule(
        notificationId,
        'Countdown $prayerName',
        'Sholat $prayerName dalam 10 menit',
        scheduledDate,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _countdownChannelId,
            'Countdown Sholat Live',
            channelDescription: 'Countdown live menjelang waktu sholat.',
            importance: Importance.low,
            enableVibration: false,
            playSound: false,
            icon: '@mipmap/ic_launcher',
            autoCancel: false,
            ongoing: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'countdown:$prayerName',
      );

      // Also schedule a native alarm to play the countdown tick at the same time
      try {
        final alarmChannel = MethodChannel('jadwalsholat.rasyid/alarm');
        await alarmChannel.invokeMethod('setExactAlarm', {
          'time': countdownStartTime.millisecondsSinceEpoch,
          'title': 'Countdown $prayerName',
          'body': 'Countdown tick for $prayerName',
          'notificationId': notificationId + 100,
          'autoPlayTick': true,
        });
        debugPrint(
          'Scheduled native tick alarm for $prayerName at $countdownStartTime',
        );
      } catch (e) {
        debugPrint('Failed to schedule native tick alarm: $e');
      }

      debugPrint(
        'Countdown start scheduled for $prayerName at: $countdownStartTime',
      );
    } catch (e) {
      debugPrint('Error scheduling countdown start for $prayerName: $e');
    }
  }

  /// Mulai countdown live
  static Future<void> startLiveCountdown(
    String prayerName,
    DateTime prayerTime,
  ) async {
    // Stop countdown yang sedang berjalan
    stopLiveCountdown();

    _currentCountdownPrayer = prayerName;
    _nextPrayerTime = prayerTime;
    _isCountdownActive = true;

    // Start ticking sound via native audio channel (looping)
    try {
      await _audioChannel.invokeMethod('playRingtone', {'res': 'tick'});
      debugPrint('Started native ticking sound for countdown');
    } catch (e) {
      debugPrint('Native ticking start failed: $e');
    }

    // Update countdown setiap detik
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      await _updateCountdownNotification();
    });

    debugPrint('Live countdown started for $prayerName');
  }

  /// Check if countdown is active (public getter)
  static bool get isCountdownActive => _isCountdownActive;

  /// Get current countdown prayer (public getter)
  static String? get currentCountdownPrayer => _currentCountdownPrayer;

  /// Update countdown notification
  static Future<void> _updateCountdownNotification() async {
    if (!_isCountdownActive ||
        _nextPrayerTime == null ||
        _currentCountdownPrayer == null) {
      return;
    }

    final now = DateTime.now();
    final difference = _nextPrayerTime!.difference(now);

    if (difference.isNegative) {
      // Waktu sholat sudah tiba, stop countdown
      stopLiveCountdown();
      return;
    }

    // Format countdown
    final hours = difference.inHours;
    final minutes = difference.inMinutes % 60;
    final seconds = difference.inSeconds % 60;

    String countdownText;
    if (hours > 0) {
      countdownText =
          '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      countdownText =
          '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }

    try {
      final notificationId =
          _countdownNotificationId + _getPrayerIndex(_currentCountdownPrayer!);

      await _notificationsPlugin.show(
        notificationId,
        'Countdown $_currentCountdownPrayer',
        'Sisa waktu: $countdownText',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _countdownChannelId,
            'Countdown Sholat Live',
            channelDescription: 'Countdown live menjelang waktu sholat.',
            importance: Importance.low,
            priority: Priority.low,
            enableVibration: false,
            playSound: false,
            icon: '@mipmap/ic_launcher',
            onlyAlertOnce: true,
            autoCancel: false,
            ongoing: true,
            showProgress: false,
          ),
        ),
        payload: 'countdown:$_currentCountdownPrayer',
      );
    } catch (e) {
      debugPrint('Error updating countdown notification: $e');
    }
  }

  /// Stop countdown live
  static void stopLiveCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _isCountdownActive = false;

    if (_currentCountdownPrayer != null) {
      final notificationId =
          _countdownNotificationId + _getPrayerIndex(_currentCountdownPrayer!);
      _notificationsPlugin.cancel(notificationId);
    }

    _currentCountdownPrayer = null;
    _nextPrayerTime = null;

    // Stop native ticking sound if running
    try {
      _audioChannel.invokeMethod('stopRingtone');
      debugPrint('Stopped native ticking sound');
    } catch (e) {
      debugPrint('Failed to stop native ticking sound: $e');
    }

    debugPrint('Live countdown stopped');
  }

  /// Stop adzan audio (public control)
  static Future<void> stopAdhanAudio() async {
    try {
      await _audioChannel.invokeMethod('stopRingtone');
      // ensure Dart player stopped too
      try {
        await _audioPlayer.stop();
      } catch (_) {}
      debugPrint('stopAdhanAudio: requested native and dart stop');
    } catch (e) {
      debugPrint('stopAdhanAudio failed: $e');
    }
  }

  /// Returns whether adhan audio is currently playing
  static Future<bool> isAdhanPlaying() async {
    try {
      return _audioPlayer.state == PlayerState.playing;
    } catch (_) {
      return false;
    }
  }

  /// Set whether adhan audio should loop when played. Persisted in SharedPreferences.
  static Future<void> setAdhanLooping(bool looping) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('loop_adhan_audio', looping);
      try {
        await _audioPlayer.setReleaseMode(looping ? ReleaseMode.loop : ReleaseMode.release);
      } catch (e) {
        debugPrint('setAdhanLooping: setReleaseMode failed: $e');
      }
    } catch (e) {
      debugPrint('Error saving loop_adhan_audio preference: $e');
    }
  }

  /// Read loop preference
  static Future<bool> isAdhanLoopingEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('loop_adhan_audio') ?? false;
  }

  /// Play audio adzan penuh dengan auto-start
  static Future<void> playFullAdhanAudio(String prayerName) async {
    try {
      debugPrint(
        '🎵 Starting auto-play adzan audio for $prayerName at ${DateTime.now()}',
      );

      // Check audio permissions first
      final permissions = await AudioPermissionService.checkAudioPermissions();
      if (!permissions['canPlayAudio']!) {
        debugPrint('❌ Audio permission denied, requesting permission...');
        final granted = await AudioPermissionService.requestAudioPermissions();
        if (!granted) {
          debugPrint('❌ Audio permission still denied after request');
          return;
        }
      }

      debugPrint('✅ Audio permissions OK, proceeding with playback...');

      // Stop audio yang sedang playing
      try {
        await _audioPlayer.stop();
      } catch (_) {}
      // Stop any native audio
      try {
        await _audioChannel.invokeMethod('stopRingtone');
      } catch (_) {}

      // Pilih file audio berdasarkan waktu sholat
      String audioFile;
      if (prayerName.toLowerCase() == 'subuh') {
        audioFile = 'audios/adzan_subuh.opus';
      } else {
        audioFile = 'audios/adzan.opus';
      }

      debugPrint('🎵 Selected audio file: $audioFile for $prayerName');

      // Set audio session mode untuk background play
      await _audioPlayer.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: true,
            contentType: AndroidContentType.music,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.gain,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: {AVAudioSessionOptions.mixWithOthers},
          ),
        ),
      );

      // Set volume maksimal dan play
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.setPlaybackRate(1.0);

      // Try native playback via notification/ringtone stream first
      var nativePlayed = false;
      try {
        // Use Android raw resource name (without extension) when calling native
        final resName = prayerName.toLowerCase() == 'subuh'
            ? 'adzan_subuh'
            : 'adzan';
        await _audioChannel.invokeMethod('playRingtone', {'res': resName});
        nativePlayed = true;
        debugPrint('✅ Native ringtone playback started for $prayerName');
      } catch (nativeErr) {
        debugPrint(
          '🔁 Native ringtone play failed, falling back to AudioPlayer: $nativeErr',
        );
      }

      if (!nativePlayed) {
        debugPrint(
          '❌ Native playback not started for $prayerName; ensure resource exists in res/raw',
        );
      }

      // Setup completion listener untuk feedback (one-time listener)
      late final StreamSubscription completeSubscription;
      completeSubscription = _audioPlayer.onPlayerComplete.listen((event) {
        debugPrint(
          '✅ Adzan audio auto-play completed for $prayerName at ${DateTime.now()}',
        );
        completeSubscription.cancel(); // Cancel to prevent memory leak
      });

      // Setup duration listener (one-time listener)
      late final StreamSubscription durationSubscription;
      durationSubscription = _audioPlayer.onDurationChanged.listen((duration) {
        debugPrint(
          '📊 Adzan audio duration: ${duration.inSeconds} seconds for $prayerName',
        );
        durationSubscription.cancel(); // Cancel after first event
      });

      // Setup position listener untuk monitoring (dengan cancel timer)
      late final StreamSubscription positionSubscription;

      positionSubscription = _audioPlayer.onPositionChanged.listen((position) {
        if (position.inSeconds % 30 == 0) {
          // Log setiap 30 detik
          debugPrint(
            '🎵 Adzan audio playing: ${position.inSeconds}s for $prayerName',
          );
        }
      });

      // Auto-cancel position listener setelah 6 menit (safety)
      Timer(const Duration(minutes: 6), () {
        positionSubscription.cancel();
        debugPrint('📢 Position listener auto-cancelled for $prayerName');
      });
    } catch (e) {
      debugPrint('❌ Error auto-playing adzan audio for $prayerName: $e');
      await ErrorLogger.instance.logError(
        message: 'Failed to auto-play adzan audio for $prayerName',
        error: e,
        stackTrace: StackTrace.current,
        context: 'auto_play_adzan_audio',
      );

      // Fallback: play short notification sound
      try {
        await playShortNotificationSound();
        debugPrint('🔄 Played fallback notification sound for $prayerName');
      } catch (fallbackError) {
        debugPrint('❌ Fallback sound also failed: $fallbackError');
      }
    }
  }

  /// Play short notification sound untuk imsak
  static Future<void> playShortNotificationSound() async {
    try {
      // Try to play short sound once via native channel
      try {
        // playCountdownTick uses a short tick sound from raw resources
        await _audioChannel.invokeMethod('playCountdownTick', {'res': 'tick'});
        debugPrint('Played short notification sound via native channel');
      } catch (e) {
        debugPrint('Native short sound failed: $e');
      }

      debugPrint('Playing short notification sound for imsak');
    } catch (e) {
      debugPrint('Error playing short notification sound: $e');
    }
  }

  /// Show foreground service notification
  static Future<void> showForegroundServiceNotification() async {
    try {
      await _notificationsPlugin.show(
        _foregroundServiceId,
        'Layanan Sholat Aktif',
        'Notifikasi sholat dan countdown berjalan di latar belakang',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _foregroundChannelId,
            'Layanan Latar Belakang Sholat',
            channelDescription:
                'Layanan untuk menjaga notifikasi sholat tetap berjalan.',
            importance: Importance.low,
            priority: Priority.low,
            enableVibration: false,
            playSound: false,
            icon: '@mipmap/ic_launcher',
            autoCancel: false,
            ongoing: true,
            showProgress: false,
          ),
        ),
      );

      debugPrint('Foreground service notification shown');
    } catch (e) {
      debugPrint('Error showing foreground service notification: $e');
    }
  }

  /// Update foreground service notification dengan status
  static Future<void> updateForegroundServiceNotification(String status) async {
    try {
      await _notificationsPlugin.show(
        _foregroundServiceId,
        'Layanan Sholat Aktif',
        status,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _foregroundChannelId,
            'Layanan Latar Belakang Sholat',
            channelDescription:
                'Layanan untuk menjaga notifikasi sholat tetap berjalan.',
            importance: Importance.low,
            priority: Priority.low,
            enableVibration: false,
            playSound: false,
            icon: '@mipmap/ic_launcher',
            autoCancel: false,
            ongoing: true,
            showProgress: false,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error updating foreground service notification: $e');
    }
  }

  /// Hide foreground service notification
  static Future<void> hideForegroundServiceNotification() async {
    await _notificationsPlugin.cancel(_foregroundServiceId);
  }

  /// Helper untuk mendapatkan index sholat
  static int _getPrayerIndex(String prayerName) {
    switch (prayerName.toLowerCase()) {
      case 'subuh':
        return 1;
      case 'dzuhur':
        return 2;
      case 'ashar':
        return 3;
      case 'maghrib':
        return 4;
      case 'isya':
        return 5;
      default:
        return 0;
    }
  }

  /// Cancel semua notifikasi
  static Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
    stopLiveCountdown();
    debugPrint('All enhanced notifications cancelled');
  }

  /// Show test notification
  static Future<void> showTestNotification() async {
    try {
      await _notificationsPlugin.show(
        9999,
        'Test Notifikasi Enhanced',
        'Notifikasi test berhasil. Ketuk untuk mendengar audio adzan.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _prayerChannelId,
            'Notifikasi Sholat Enhanced',
            channelDescription: 'Test notifikasi enhanced.',
            importance: Importance.max,
            priority: Priority.high,
            enableVibration: true,
            playSound: true,
            icon: '@mipmap/ic_launcher',
          ),
        ),
        payload: 'test:notification',
      );

      debugPrint('Test enhanced notification shown');
    } catch (e) {
      debugPrint('Error showing test enhanced notification: $e');
    }
  }

  /// Jadwalkan alarm untuk auto play audio azan
  static Future<void> _scheduleAutoPlayAlarm(
    String prayerName,
    DateTime prayerTime,
  ) async {
    try {
      // Use native AlarmManager via method channel so alarm fires even when app is killed
      final alarmChannel = MethodChannel('jadwalsholat.rasyid/alarm');
      await alarmChannel.invokeMethod('setExactAlarm', {
        'time': prayerTime.millisecondsSinceEpoch,
        'title': 'Waktu $prayerName',
        'body': 'Auto-play Adzan untuk $prayerName',
        'notificationId': _baseNotificationId + _getPrayerIndex(prayerName),
        // custom flag to indicate this alarm should auto-play adzan
        'autoPlayPrayer': prayerName,
      });

      debugPrint(
        'Auto play alarm scheduled via AlarmManager for $prayerName at $prayerTime',
      );
    } catch (e) {
      debugPrint('Error scheduling auto play alarm for $prayerName: $e');
    }
  }

  /// Update notifikasi dengan status audio
  static Future<void> _updateNotificationWithAudioStatus(
    String prayerName,
    String status,
  ) async {
    try {
      final notificationId = _baseNotificationId + _getPrayerIndex(prayerName);

      await _notificationsPlugin.show(
        notificationId,
        'Waktu $prayerName',
        status,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _prayerChannelId,
            'Notifikasi Sholat Enhanced',
            channelDescription: 'Notifikasi untuk waktu sholat.',
            importance: Importance.max,
            enableVibration: false, // Tidak vibrate untuk update status
            playSound: false,
            icon: '@mipmap/ic_launcher',
            enableLights: true,
            ledColor: Color(0xFF4DB6AC),
            ledOnMs: 1000,
            ledOffMs: 500,
            autoCancel: false,
            ongoing: true,
          ),
        ),
      );

      debugPrint('Updated notification for $prayerName: $status');
    } catch (e) {
      debugPrint('Error updating notification status for $prayerName: $e');
    }
  }

  /// Public method untuk update notification status (untuk background service)
  static Future<void> updateNotificationWithAudioStatus(
    String prayerName,
    String status,
  ) async {
    await _updateNotificationWithAudioStatus(prayerName, status);
  }

  /// Cleanup resources
  static Future<void> dispose() async {
    _countdownTimer?.cancel();
    _dailyRefreshTimer?.cancel();
    await _audioPlayer.dispose();
    debugPrint('NotificationServiceEnhanced disposed');
  }
}
