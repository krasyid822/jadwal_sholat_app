import 'package:flutter_test/flutter_test.dart';
import 'package:jadwal_sholat_app/services/notification_service_enhanced.dart';
import 'package:jadwal_sholat_app/services/location_cache_service.dart';
import 'package:jadwal_sholat_app/services/background_service_enhanced.dart';
import 'package:jadwal_sholat_app/config/enhanced_notification_config.dart';

void main() {
  group('Enhanced Notification System Tests', () {
    test('Enhanced Notification Config Test', () {
      // Test prayer audio file selection
      expect(
        EnhancedNotificationConfig.getPrayerAudioFile('Subuh'),
        equals('audios/adzan_subuh.opus'),
      );
      expect(
        EnhancedNotificationConfig.getPrayerAudioFile('Dzuhur'),
        equals('audios/adzan.opus'),
      );

      // Test notification ID generation
      expect(
        EnhancedNotificationConfig.getPrayerNotificationId('Subuh'),
        equals(1001),
      );
      expect(
        EnhancedNotificationConfig.getCountdownNotificationId('Dzuhur'),
        equals(2002),
      );

      // Test message formatting
      final prayerMessage = EnhancedNotificationConfig.formatPrayerMessage(
        'Dzuhur',
      );
      expect(prayerMessage, contains('Dzuhur'));
      expect(prayerMessage, contains('Ketuk untuk mendengar adzan'));

      final countdownMessage =
          EnhancedNotificationConfig.formatCountdownMessage('Ashar', '05:30');
      expect(countdownMessage, contains('Ashar'));
      expect(countdownMessage, contains('05:30'));
    });

    test('Location Cache Service Test', () async {
      // Test cache validity
      final isValid = await LocationCacheService.isCacheValid();
      expect(isValid, isA<bool>());

      // Test cache summary
      final summary = await LocationCacheService.getCacheSummary();
      expect(summary, isA<String>());
      expect(summary.isNotEmpty, isTrue);
    });

    test('Background Service Status Test', () async {
      // Test service status check
      final isRunning = await BackgroundServiceEnhanced.isServiceRunning();
      expect(isRunning, isA<bool>());
    });

    test('Notification Service Enhanced Getters Test', () {
      // Test countdown status getters
      expect(NotificationServiceEnhanced.isCountdownActive, isA<bool>());
      expect(
        NotificationServiceEnhanced.currentCountdownPrayer,
        isA<String?>(),
      );
    });

    test('Configuration Validation Test', () {
      // Test default settings
      expect(
        EnhancedNotificationConfig.defaultSettings['prayer_notifications'],
        isTrue,
      );
      expect(
        EnhancedNotificationConfig.defaultSettings['countdown_notifications'],
        isTrue,
      );
      expect(
        EnhancedNotificationConfig.defaultSettings['imsak_notifications'],
        isTrue,
      );

      // Test timing configuration
      expect(
        EnhancedNotificationConfig.countdownStartDuration.inMinutes,
        equals(10),
      );
      expect(EnhancedNotificationConfig.imsakBeforeSubuh.inMinutes, equals(20));

      // Test channel IDs
      expect(EnhancedNotificationConfig.prayerChannelId, isNotEmpty);
      expect(EnhancedNotificationConfig.countdownChannelId, isNotEmpty);
      expect(EnhancedNotificationConfig.imsakChannelId, isNotEmpty);
    });
  });

  group('Prayer Time Calculation Tests', () {
    test('Prayer Index Mapping Test', () {
      expect(EnhancedNotificationConfig.prayerNameToIndex['Subuh'], equals(1));
      expect(EnhancedNotificationConfig.prayerNameToIndex['Dzuhur'], equals(2));
      expect(EnhancedNotificationConfig.prayerNameToIndex['Ashar'], equals(3));
      expect(
        EnhancedNotificationConfig.prayerNameToIndex['Maghrib'],
        equals(4),
      );
      expect(EnhancedNotificationConfig.prayerNameToIndex['Isya'], equals(5));
    });
  });

  group('Audio Configuration Tests', () {
    test('Audio File Paths Test', () {
      expect(
        EnhancedNotificationConfig.adzanSubuhFile,
        equals('audios/adzan_subuh.opus'),
      );
      expect(
        EnhancedNotificationConfig.adzanStandardFile,
        equals('audios/adzan.opus'),
      );
    });

    test('Audio Settings Test', () {
      expect(EnhancedNotificationConfig.defaultAdzanVolume, equals(1.0));
      expect(EnhancedNotificationConfig.defaultPlaybackRate, equals(1.0));
      expect(
        EnhancedNotificationConfig.shortNotificationAudioDuration.inSeconds,
        equals(10),
      );
    });
  });

  group('Notification Content Tests', () {
    test('Notification Titles Test', () {
      expect(
        EnhancedNotificationConfig.notificationTitles['prayer'],
        equals('Waktu Sholat'),
      );
      expect(
        EnhancedNotificationConfig.notificationTitles['countdown'],
        equals('Countdown Sholat'),
      );
      expect(
        EnhancedNotificationConfig.notificationTitles['imsak'],
        equals('Waktu Imsak'),
      );
    });

    test('Notification Messages Test', () {
      expect(
        EnhancedNotificationConfig.notificationMessages['imsak'],
        contains('imsak'),
      );
      expect(
        EnhancedNotificationConfig.notificationMessages['service_active'],
        contains('latar belakang'),
      );
    });
  });
}
