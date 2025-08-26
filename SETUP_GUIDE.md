# Setup Enhanced Prayer Notification System

## Instalasi dan Konfigurasi

### 1. Dependencies yang Diperlukan

Pastikan `pubspec.yaml` sudah memiliki dependencies berikut:

```yaml
dependencies:
  # Audio untuk Adzan
  audioplayers: ^6.1.0
  
  # Notifikasi & Background Service
  flutter_local_notifications: ^19.4.0
  flutter_background_service: ^5.0.1
  flutter_background_service_android: ^6.3.1
  
  # Permission Management
  permission_handler: ^12.0.1
  
  # Location Services
  geolocator: ^13.0.4
  geocoding: ^4.0.0
  
  # Storage & Utilities
  shared_preferences: ^2.2.3
  
  # Prayer Time Calculation
  adhan: ^2.0.0+1
  timezone: ^0.10.1

assets:
  - assets/audios/
```

### 2. File Audio yang Diperlukan

Pastikan file audio adzan ada di folder `assets/audios/`:

```
assets/
  audios/
    adzan.opus         # Audio adzan standar (Dzuhur, Ashar, Maghrib, Isya)
    adzan_subuh.opus   # Audio adzan khusus Subuh
```

**Format Audio yang Disarankan:**
- Format: OPUS (ukuran kecil, kualitas tinggi)
- Durasi: 3-5 menit (audio adzan lengkap)
- Bitrate: 64-128 kbps
- Sample Rate: 44.1 kHz

### 3. Permissions di AndroidManifest.xml

Tambahkan permissions berikut di `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Location Permissions -->
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    
    <!-- Notification Permissions -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.VIBRATE" />
    
    <!-- Exact Alarm Permission (Android 12+) -->
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
    <uses-permission android:name="android.permission.USE_EXACT_ALARM" />
    
    <!-- Background Service Permissions -->
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    
    <!-- Battery Optimization -->
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
    
    <!-- Boot Receiver (Optional) -->
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
    
    <!-- Audio Permissions -->
    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
    
    <application
        android:name="${applicationName}"
        android:exported="false"
        android:icon="@mipmap/ic_launcher">
        
        <!-- Main Activity -->
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme">
            <!-- ... intent filters ... -->
        </activity>
        
        <!-- Background Service -->
        <service
            android:name="id.flutter.flutter_background_service.BackgroundService"
            android:exported="false"
            android:foregroundServiceType="location|dataSync" />
            
        <!-- Boot Receiver (Optional) -->
        <receiver android:name="id.flutter.flutter_background_service.BootReceiver"
            android:exported="false">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
            </intent-filter>
        </receiver>
    </application>
</manifest>
```

### 4. Inisialisasi di main.dart

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize timezone
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Jakarta'));
  
  // Initialize services
  await ErrorLogger.instance.initialize();
  await NotificationServiceEnhanced.initialize();
  await BackgroundServiceEnhanced.initializeEnhancedService();
  
  runApp(MyApp());
}
```

### 5. Setup Permission Request

Tambahkan permission request di awal aplikasi:

```dart
// Di initState() atau onAppStart
await NotificationServiceEnhanced.requestEnhancedPermissions();
```

### 6. Mengaktifkan Enhanced Service

```dart
// Start enhanced background service
final success = await BackgroundServiceEnhanced.startEnhancedService();

if (success) {
  print('Enhanced service started successfully');
} else {
  print('Failed to start enhanced service');
}
```

## Konfigurasi Custom

### 1. Mengubah Timing Default

Edit file `lib/config/enhanced_notification_config.dart`:

```dart
class EnhancedNotificationConfig {
  // Ubah timing countdown (default 10 menit)
  static const Duration countdownStartDuration = Duration(minutes: 15);
  
  // Ubah timing imsak (default 20 menit sebelum Subuh)
  static const Duration imsakBeforeSubuh = Duration(minutes: 30);
  
  // Ubah interval refresh lokasi (default 1 jam)
  static const Duration locationRefreshInterval = Duration(hours: 2);
}
```

### 2. Mengubah File Audio

```dart
class EnhancedNotificationConfig {
  static const String adzanSubuhFile = 'audios/adzan_subuh_custom.mp3';
  static const String adzanStandardFile = 'audios/adzan_custom.mp3';
}
```

### 3. Custom Notification Messages

```dart
class EnhancedNotificationConfig {
  static const Map<String, String> notificationMessages = {
    'prayer_template': 'Waktu {prayer} telah tiba. Silakan melaksanakan sholat.',
    'countdown_template': '{time} lagi waktu sholat {prayer}',
    'imsak': 'Waktu imsak telah tiba. Berhenti makan dan minum.',
  };
}
```

## Testing Setup

### 1. Test Audio Playback

```dart
// Test audio adzan
await NotificationServiceEnhanced.playFullAdhanAudio('Dzuhur');

// Test audio imsak
await NotificationServiceEnhanced.playShortNotificationSound();
```

### 2. Test Notifications

```dart
// Test instant notification
await NotificationServiceEnhanced.showTestNotification();

// Test countdown
await NotificationServiceEnhanced.startLiveCountdown(
  'Dzuhur', 
  DateTime.now().add(Duration(minutes: 5))
);
```

### 3. Test Location Cache

```dart
// Check cache status
final summary = await LocationCacheService.getCacheSummary();
print(summary);

// Force refresh cache
await LocationCacheService.forceRefreshCache();
```

### 4. Test Background Service

```dart
// Check service status
final isRunning = await BackgroundServiceEnhanced.isServiceRunning();
print('Service running: $isRunning');

// Start/Stop service
await BackgroundServiceEnhanced.startEnhancedService();
await BackgroundServiceEnhanced.stopEnhancedService();
```

## Troubleshooting Setup

### 1. Audio Tidak Dimainkan

**Kemungkinan Penyebab:**
- File audio tidak ada di assets/audios/
- Format audio tidak didukung
- Permission audio tidak diberikan

**Solusi:**
```bash
# Verify audio files exist
ls assets/audios/

# Check audio format
ffprobe assets/audios/adzan.opus

# Request audio permission
await Permission.audio.request();
```

### 2. Notifikasi Tidak Muncul

**Kemungkinan Penyebab:**
- Exact alarm permission tidak diberikan
- Battery optimization aktif
- Notification channel tidak dibuat

**Solusi:**
```dart
// Check and request permissions
final notifStatus = await Permission.notification.request();
final exactAlarmStatus = await Permission.scheduleExactAlarm.request();
final batteryStatus = await Permission.ignoreBatteryOptimizations.request();

print('Notification: ${notifStatus.name}');
print('Exact Alarm: ${exactAlarmStatus.name}');
print('Battery: ${batteryStatus.name}');
```

### 3. Background Service Mati

**Kemungkinan Penyebab:**
- Auto-start permission tidak diberikan
- Battery optimization membunuh service
- Foreground notification tidak aktif

**Solusi:**
```dart
// Show foreground notification
await NotificationServiceEnhanced.showForegroundServiceNotification();

// Check service status periodically
Timer.periodic(Duration(minutes: 5), (timer) async {
  final isRunning = await BackgroundServiceEnhanced.isServiceRunning();
  if (!isRunning) {
    await BackgroundServiceEnhanced.startEnhancedService();
  }
});
```

### 4. Location Update Gagal

**Kemungkinan Penyebab:**
- Location permission tidak diberikan
- GPS disabled
- Network timeout

**Solusi:**
```dart
// Check location permission
final locationStatus = await Permission.location.request();

// Check GPS enabled
final serviceEnabled = await Geolocator.isLocationServiceEnabled();

// Use cached location as fallback
if (!serviceEnabled) {
  final cached = await LocationCacheService.getCachedLocation();
  if (cached != null) {
    // Use cached location
  }
}
```

## Optimisasi Performance

### 1. Battery Usage Optimization

```dart
// Minimize background processing
static const Duration backgroundCheckInterval = Duration(minutes: 5);

// Use cached data when possible
final cached = await LocationCacheService.getCachedLocation();
if (cached != null && await LocationCacheService.isCacheValid()) {
  // Use cached data instead of GPS
}
```

### 2. Memory Management

```dart
// Dispose resources properly
@override
void dispose() {
  NotificationServiceEnhanced.dispose();
  super.dispose();
}
```

### 3. Network Usage Minimization

```dart
// All calculations done locally after initial setup
// No network required for prayer time calculations
// Optional location refresh (user controlled)
```

## Deployment Checklist

- [ ] Audio files added to assets/audios/
- [ ] Permissions added to AndroidManifest.xml
- [ ] pubspec.yaml dependencies updated
- [ ] Service initialization in main.dart
- [ ] Permission requests implemented
- [ ] Test notifications working
- [ ] Audio playback working
- [ ] Background service running
- [ ] Location cache functioning
- [ ] Settings screen accessible
- [ ] Error logging operational

## Maintenance

### Daily Monitoring

```dart
// Check error logs
final errors = await ErrorLogger.instance.getStoredErrors();

// Check service status
final isRunning = await BackgroundServiceEnhanced.isServiceRunning();

// Check cache status
final cacheValid = await LocationCacheService.isCacheValid();
```

### Weekly Tasks

- Review stored error logs
- Verify audio files integrity
- Check notification delivery rates
- Monitor battery usage impact

### Monthly Updates

- Update prayer time calculations if needed
- Review and update cached locations
- Check for new Android permission requirements
- Verify compatibility with OS updates
