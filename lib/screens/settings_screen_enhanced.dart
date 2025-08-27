import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';
import '../services/notification_service_enhanced.dart';
import '../services/background_service_enhanced.dart';
import 'audio_debug_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _prayerNotifications = true;
  bool _countdownNotifications = true;
  bool _imsakNotifications = true;
  bool _autoLocationRefresh = false;
  bool _enhancedServiceEnabled = false;
  bool _autoPlayAdhanAudio = true; // New: Auto-play adhan audio
  bool _useNativeRingtonePlayback = true;
  bool _enableWatchdogRestart = true;
  bool _enableLocationCache = false;
  bool _enableElevationCache = false;
  bool _loopAdhanAudio = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _prayerNotifications = prefs.getBool('prayer_notifications') ?? true;
      _countdownNotifications =
          prefs.getBool('countdown_notifications') ?? true;
      _imsakNotifications = prefs.getBool('imsak_notifications') ?? true;
      _autoLocationRefresh = prefs.getBool('auto_location_refresh') ?? false;
      _enhancedServiceEnabled =
          prefs.getBool('enhanced_service_enabled') ?? false;
      _autoPlayAdhanAudio = prefs.getBool('auto_play_adhan_audio') ?? true;
      _useNativeRingtonePlayback =
          prefs.getBool('use_native_ringtone_playback') ?? true;
      _enableWatchdogRestart = prefs.getBool('enable_watchdog_restart') ?? true;
  _enableLocationCache = prefs.getBool('enable_location_cache') ?? false;
  _enableElevationCache = prefs.getBool('enable_elevation_cache') ?? false;
  _loopAdhanAudio = prefs.getBool('loop_adhan_audio') ?? false;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('prayer_notifications', _prayerNotifications);
    await prefs.setBool('countdown_notifications', _countdownNotifications);
    await prefs.setBool('imsak_notifications', _imsakNotifications);
    await prefs.setBool('auto_location_refresh', _autoLocationRefresh);
    await prefs.setBool('enhanced_service_enabled', _enhancedServiceEnabled);
    await prefs.setBool('auto_play_adhan_audio', _autoPlayAdhanAudio);
    await prefs.setBool(
      'use_native_ringtone_playback',
      _useNativeRingtonePlayback,
    );
    await prefs.setBool('enable_watchdog_restart', _enableWatchdogRestart);
  await prefs.setBool('enable_location_cache', _enableLocationCache);
  await prefs.setBool('enable_elevation_cache', _enableElevationCache);
  await prefs.setBool('loop_adhan_audio', _loopAdhanAudio);
  }

  Future<void> _testEnhancedNotification() async {
    setState(() => _isLoading = true);

    await NotificationServiceEnhanced.showTestNotification();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Test enhanced notification sent!'),
          backgroundColor: Color(0xFF4DB6AC),
        ),
      );
    }

    setState(() => _isLoading = false);
  }

  Future<void> _toggleEnhancedService() async {
    setState(() => _isLoading = true);

    try {
      if (_enhancedServiceEnabled) {
        // Start enhanced service
        final success = await BackgroundServiceEnhanced.startEnhancedService();
        if (success) {
          await _saveSettings();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Enhanced background service started'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          setState(() => _enhancedServiceEnabled = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to start enhanced service'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } else {
        // Stop enhanced service
        final success = await BackgroundServiceEnhanced.stopEnhancedService();
        if (success) {
          await _saveSettings();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Enhanced background service stopped'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }
    } catch (e) {
      setState(() => _enhancedServiceEnabled = !_enhancedServiceEnabled);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error toggling enhanced service: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    setState(() => _isLoading = false);
  }

  Future<void> _testInstantNotification() async {
    setState(() => _isLoading = true);

    await NotificationService.showTestNotification();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Test notifikasi dikirim!'),
          backgroundColor: Color(0xFF4DB6AC),
        ),
      );
    }

    setState(() => _isLoading = false);
  }

  Future<void> _testScheduledNotification() async {
    setState(() => _isLoading = true);

    await NotificationService.showScheduledTestNotification();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Test notifikasi terjadwal (10 detik) berhasil dijadwalkan!',
          ),
          backgroundColor: Color(0xFF4DB6AC),
          duration: Duration(seconds: 3),
        ),
      );
    }

    setState(() => _isLoading = false);
  }

  Future<void> _checkPermissions() async {
    setState(() => _isLoading = true);

    await NotificationService.printNotificationDebugInfo();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debug info dicetak ke console. Periksa log aplikasi.'),
          backgroundColor: Color(0xFF4DB6AC),
        ),
      );
    }

    setState(() => _isLoading = false);
  }

  Future<void> _requestPermissions() async {
    setState(() => _isLoading = true);

    final granted =
        await NotificationServiceEnhanced.requestEnhancedPermissions();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            granted
                ? 'Permission berhasil diberikan!'
                : 'Beberapa permission gagal. Cek pengaturan sistem.',
          ),
          backgroundColor: granted ? Colors.green : Colors.orange,
        ),
      );
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Pengaturan'),
        backgroundColor: const Color(0xFF1E1E1E),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF4DB6AC)),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSection('Notifikasi Enhanced', [
                  SwitchListTile(
                    title: const Text(
                      'Notifikasi Sholat',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Aktifkan notifikasi untuk waktu sholat dengan audio adzan penuh',
                      style: TextStyle(color: Colors.grey),
                    ),
                    value: _prayerNotifications,
                    activeThumbColor: const Color(0xFF4DB6AC),
                    onChanged: (value) {
                      setState(() => _prayerNotifications = value);
                      _saveSettings();
                    },
                  ),
                  SwitchListTile(
                    title: const Text(
                      'Countdown Live',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Tampilkan countdown live 10 menit sebelum sholat',
                      style: TextStyle(color: Colors.grey),
                    ),
                    value: _countdownNotifications,
                    activeThumbColor: const Color(0xFF4DB6AC),
                    onChanged: (value) {
                      setState(() => _countdownNotifications = value);
                      _saveSettings();
                    },
                  ),
                  SwitchListTile(
                    title: const Text(
                      'Notifikasi Imsak',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Aktifkan notifikasi untuk waktu imsak (10 menit sebelum Subuh)',
                      style: TextStyle(color: Colors.grey),
                    ),
                    value: _imsakNotifications,
                    activeThumbColor: const Color(0xFF4DB6AC),
                    onChanged: (value) {
                      setState(() => _imsakNotifications = value);
                      _saveSettings();
                    },
                  ),
                ]),

                const SizedBox(height: 16),

                _buildSection('Layanan Latar Belakang Enhanced', [
                  SwitchListTile(
                    title: const Text(
                      'Enhanced Background Service',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Aktifkan layanan enhanced untuk notifikasi yang lebih stabil',
                      style: TextStyle(color: Colors.grey),
                    ),
                    value: _enhancedServiceEnabled,
                    activeThumbColor: const Color(0xFF4DB6AC),
                    onChanged: (value) {
                      setState(() => _enhancedServiceEnabled = value);
                      _toggleEnhancedService();
                    },
                  ),
                  SwitchListTile(
                    title: const Text(
                      'Auto-Play Audio Azan',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Putar audio azan otomatis saat waktu sholat tanpa perlu mengetuk notifikasi',
                      style: TextStyle(color: Colors.grey),
                    ),
                    value: _autoPlayAdhanAudio,
                    activeThumbColor: const Color(0xFF4DB6AC),
                    onChanged: (value) {
                      setState(() => _autoPlayAdhanAudio = value);
                      _saveSettings();
                    },
                  ),
                  SwitchListTile(
                    title: const Text(
                      'Auto Refresh Lokasi',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Perbarui lokasi otomatis setiap jam untuk akurasi waktu sholat',
                      style: TextStyle(color: Colors.grey),
                    ),
                    value: _autoLocationRefresh,
                    activeThumbColor: const Color(0xFF4DB6AC),
                    onChanged: (value) {
                      setState(() => _autoLocationRefresh = value);
                      _saveSettings();
                    },
                  ),
                  SwitchListTile(
                    title: const Text(
                      'Enable Location Cache',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Simpan lokasi terakhir untuk fallback jika GPS tidak tersedia',
                      style: TextStyle(color: Colors.grey),
                    ),
                    value: _enableLocationCache,
                    activeThumbColor: const Color(0xFF4DB6AC),
                    onChanged: (value) {
                      setState(() => _enableLocationCache = value);
                      _saveSettings();
                    },
                  ),
                  SwitchListTile(
                    title: const Text(
                      'Enable Elevation Cache',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Simpan elevasi terakhir untuk digunakan sebagai fallback',
                      style: TextStyle(color: Colors.grey),
                    ),
                    value: _enableElevationCache,
                    activeThumbColor: const Color(0xFF4DB6AC),
                    onChanged: (value) {
                      setState(() => _enableElevationCache = value);
                      _saveSettings();
                    },
                  ),
                  SwitchListTile(
                    title: const Text(
                      'Use Native Ringtone Playback',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Putar adzan melalui channel notifikasi (system notification volume).',
                      style: TextStyle(color: Colors.grey),
                    ),
                    value: _useNativeRingtonePlayback,
                    activeThumbColor: const Color(0xFF4DB6AC),
                    onChanged: (value) {
                      setState(() => _useNativeRingtonePlayback = value);
                      _saveSettings();
                    },
                  ),
                  SwitchListTile(
                    title: const Text(
                      'Loop Audio Azan',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Putar audio azan secara berulang (loop). Default: mati',
                      style: TextStyle(color: Colors.grey),
                    ),
                    value: _loopAdhanAudio,
                    activeThumbColor: const Color(0xFF4DB6AC),
                    onChanged: (value) async {
                      setState(() => _loopAdhanAudio = value);
                      await NotificationServiceEnhanced.setAdhanLooping(value);
                      _saveSettings();
                    },
                  ),
                  SwitchListTile(
                    title: const Text(
                      'Enable Watchdog Restart',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Biarkan layanan background mencoba restart otomatis bila terhenti.',
                      style: TextStyle(color: Colors.grey),
                    ),
                    value: _enableWatchdogRestart,
                    activeThumbColor: const Color(0xFF4DB6AC),
                    onChanged: (value) async {
                      setState(() => _enableWatchdogRestart = value);
                      await _saveSettings();
                      // If toggling watchdog off/on, inform background service
                      if (_enhancedServiceEnabled) {
                        if (value) {
                          // ensure service started so watchdog runs
                          await BackgroundServiceEnhanced.restartEnhancedService();
                        } else {
                          // restart service to pick up change and stop watchdog
                          await BackgroundServiceEnhanced.restartEnhancedService();
                        }
                      }
                    },
                  ),
                ]),

                const SizedBox(height: 16),

                _buildSection('Test & Debug', [
                  _buildActionTile(
                    icon: Icons.notifications_active,
                    title: 'Test Enhanced Notification',
                    subtitle: 'Test notifikasi enhanced dengan audio adzan',
                    onTap: _testEnhancedNotification,
                  ),
                  _buildActionTile(
                    icon: Icons.notification_add,
                    title: 'Test Notifikasi Instan',
                    subtitle: 'Kirim test notifikasi sekarang',
                    onTap: _testInstantNotification,
                  ),
                  _buildActionTile(
                    icon: Icons.schedule,
                    title: 'Test Notifikasi Terjadwal',
                    subtitle: 'Jadwalkan test notifikasi (10 detik)',
                    onTap: _testScheduledNotification,
                  ),
                  _buildActionTile(
                    icon: Icons.bug_report,
                    title: 'Debug Info',
                    subtitle: 'Tampilkan informasi debug ke console',
                    onTap: _checkPermissions,
                  ),
                  _buildActionTile(
                    icon: Icons.audiotrack,
                    title: 'Audio Debug',
                    subtitle: 'Debug auto-play audio azan',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AudioDebugScreen(),
                        ),
                      );
                    },
                  ),
                ]),

                const SizedBox(height: 16),

                _buildSection('Permissions', [
                  _buildActionTile(
                    icon: Icons.security,
                    title: 'Request Enhanced Permissions',
                    subtitle: 'Minta semua permission yang diperlukan',
                    onTap: _requestPermissions,
                  ),
                ]),

                const SizedBox(height: 16),

                _buildSection('Informasi Penting', [
                  _buildInfoTile(
                    icon: Icons.battery_saver,
                    title: 'Battery Optimization',
                    subtitle:
                        'Pastikan aplikasi dikecualikan dari optimisasi baterai',
                  ),
                  _buildInfoTile(
                    icon: Icons.refresh,
                    title: 'Background App Refresh',
                    subtitle:
                        'Pastikan aplikasi diizinkan berjalan di background',
                  ),
                  _buildInfoTile(
                    icon: Icons.alarm,
                    title: 'Exact Alarm',
                    subtitle: 'Berikan permission untuk exact alarm scheduling',
                  ),
                ]),
              ],
            ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Card(
      color: const Color(0xFF1E1E1E),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              title,
              style: const TextStyle(
                color: Color(0xFF4DB6AC),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF4DB6AC)),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.orange),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey)),
    );
  }
}
