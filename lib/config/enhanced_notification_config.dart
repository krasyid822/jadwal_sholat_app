class EnhancedNotificationConfig {
  // Audio Configuration
  static const String adzanSubuhFile = 'audios/adzan_subuh.opus';
  static const String adzanStandardFile = 'audios/adzan.opus';

  // Timing Configuration
  static const Duration countdownStartDuration = Duration(minutes: 10);
  static const Duration imsakBeforeSubuh = Duration(minutes: 10);
  static const Duration countdownUpdateInterval = Duration(seconds: 1);
  static const Duration backgroundCheckInterval = Duration(minutes: 1);
  static const Duration locationRefreshInterval = Duration(hours: 1);
  static const Duration dailyNotificationRefresh = Duration(hours: 24);

  // Notification IDs
  static const int basePrayerNotificationId = 1000;
  static const int baseCountdownNotificationId = 2000;
  static const int imsakNotificationId = 3000;
  static const int foregroundServiceId = 4000;

  // Channel IDs
  static const String prayerChannelId = 'prayer_enhanced_channel';
  static const String countdownChannelId = 'countdown_enhanced_channel';
  static const String imsakChannelId = 'imsak_channel';
  static const String foregroundChannelId =
      'foreground_service_enhanced_channel';

  // Cache Configuration
  static const Duration cacheValidityDuration = Duration(hours: 24);
  static const int maxStoredErrors = 50;

  // Audio Configuration
  static const double defaultAdzanVolume = 1.0;
  static const double defaultPlaybackRate = 1.0;
  static const Duration shortNotificationAudioDuration = Duration(seconds: 10);

  // Location Configuration
  static const double minimumLocationAccuracy = 100.0; // meters
  static const Duration locationTimeoutDuration = Duration(seconds: 30);

  // Prayer Names Mapping
  static const Map<String, int> prayerNameToIndex = {
    'Subuh': 1,
    'Dzuhur': 2,
    'Ashar': 3,
    'Maghrib': 4,
    'Isya': 5,
  };

  // Default Settings
  static const Map<String, bool> defaultSettings = {
    'prayer_notifications': true,
    'countdown_notifications': true,
    'imsak_notifications': true,
    'auto_location_refresh': false,
    'enhanced_service_enabled': false,
  };

  // Notification Content
  static const Map<String, String> notificationTitles = {
    'prayer': 'Waktu Sholat',
    'countdown': 'Countdown Sholat',
    'imsak': 'Waktu Imsak',
    'service': 'Layanan Sholat Aktif',
  };

  static const Map<String, String> notificationMessages = {
    'prayer_template':
        'Telah masuk waktu sholat {prayer}. Ketuk untuk mendengar adzan.',
    'countdown_template': 'Sholat {prayer} dalam {time}',
    'imsak': 'Mulai waktu imsak. Saatnya menahan diri dari makan dan minum.',
    'service_active':
        'Notifikasi sholat dan countdown berjalan di latar belakang',
  };

  // Colors
  static const int primaryColorValue = 0xFF4DB6AC;
  static const int ledColorValue = 0xFF4DB6AC;

  // Helper methods
  static String getPrayerAudioFile(String prayerName) {
    return prayerName.toLowerCase() == 'subuh'
        ? adzanSubuhFile
        : adzanStandardFile;
  }

  static int getPrayerNotificationId(String prayerName) {
    final index = prayerNameToIndex[prayerName] ?? 0;
    return basePrayerNotificationId + index;
  }

  static int getCountdownNotificationId(String prayerName) {
    final index = prayerNameToIndex[prayerName] ?? 0;
    return baseCountdownNotificationId + index;
  }

  static String formatCountdownMessage(String prayerName, String timeLeft) {
    return notificationMessages['countdown_template']!
        .replaceAll('{prayer}', prayerName)
        .replaceAll('{time}', timeLeft);
  }

  static String formatPrayerMessage(String prayerName) {
    return notificationMessages['prayer_template']!.replaceAll(
      '{prayer}',
      prayerName,
    );
  }
}
