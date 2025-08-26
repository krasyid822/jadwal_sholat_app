import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service_enhanced.dart';
import '../services/background_service_enhanced.dart';
import '../services/audio_permission_service.dart';

/// Screen untuk debugging auto-play audio azan
class AudioDebugScreen extends StatefulWidget {
  const AudioDebugScreen({super.key});

  @override
  State<AudioDebugScreen> createState() => _AudioDebugScreenState();
}

class _AudioDebugScreenState extends State<AudioDebugScreen> {
  bool _autoPlayEnabled = true;
  bool _serviceRunning = false;
  Map<String, String> _prayerTimes = {};
  Map<String, bool> _audioPlayedFlags = {};
  Map<String, bool> _audioPermissions = {
    'microphone': false,
    'notification': false,
    'canPlayAudio': false,
  };
  String _debugLog = '';

  @override
  void initState() {
    super.initState();
    _loadDebugInfo();
  }

  Future<void> _loadDebugInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();

    // Load audio permissions
    final permissions = await AudioPermissionService.checkAudioPermissions();

    setState(() {
      _autoPlayEnabled = prefs.getBool('auto_play_adhan_audio') ?? true;
      _audioPermissions = permissions;

      // Load prayer times
      _prayerTimes = {
        'Subuh': prefs.getString('prayer_time_subuh') ?? 'Not set',
        'Dzuhur': prefs.getString('prayer_time_dzuhur') ?? 'Not set',
        'Ashar': prefs.getString('prayer_time_ashar') ?? 'Not set',
        'Maghrib': prefs.getString('prayer_time_maghrib') ?? 'Not set',
        'Isya': prefs.getString('prayer_time_isya') ?? 'Not set',
      };

      // Load audio played flags for today
      _audioPlayedFlags = {
        'Subuh':
            prefs.getBool(
              'audio_played_subuh_${now.year}_${now.month}_${now.day}',
            ) ??
            false,
        'Dzuhur':
            prefs.getBool(
              'audio_played_dzuhur_${now.year}_${now.month}_${now.day}',
            ) ??
            false,
        'Ashar':
            prefs.getBool(
              'audio_played_ashar_${now.year}_${now.month}_${now.day}',
            ) ??
            false,
        'Maghrib':
            prefs.getBool(
              'audio_played_maghrib_${now.year}_${now.month}_${now.day}',
            ) ??
            false,
        'Isya':
            prefs.getBool(
              'audio_played_isya_${now.year}_${now.month}_${now.day}',
            ) ??
            false,
      };
    });

    // Check service status
    _serviceRunning = await BackgroundServiceEnhanced.isServiceRunning();
    setState(() {});
  }

  Future<void> _testAudioPlay(String prayerName) async {
    setState(() {
      _debugLog += '${DateTime.now()}: Testing audio for $prayerName...\n';
    });

    try {
      await NotificationServiceEnhanced.playFullAdhanAudio(prayerName);
      setState(() {
        _debugLog +=
            '${DateTime.now()}: ✅ Audio $prayerName started successfully\n';
      });
    } catch (e) {
      setState(() {
        _debugLog += '${DateTime.now()}: ❌ Error playing $prayerName: $e\n';
      });
    }
  }

  Future<void> _resetAudioFlags() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();

    final prayers = ['subuh', 'dzuhur', 'ashar', 'maghrib', 'isya'];
    for (final prayer in prayers) {
      await prefs.remove(
        'audio_played_${prayer}_${now.year}_${now.month}_${now.day}',
      );
    }

    setState(() {
      _debugLog += '${DateTime.now()}: 🔄 Audio flags reset for today\n';
    });

    await _loadDebugInfo();
  }

  Future<void> _toggleAutoPlay() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_play_adhan_audio', !_autoPlayEnabled);

    setState(() {
      _autoPlayEnabled = !_autoPlayEnabled;
      _debugLog +=
          '${DateTime.now()}: Auto-play ${_autoPlayEnabled ? 'ENABLED' : 'DISABLED'}\n';
    });
  }

  Future<void> _restartService() async {
    setState(() {
      _debugLog += '${DateTime.now()}: Restarting background service...\n';
    });

    try {
      await BackgroundServiceEnhanced.stopEnhancedService();
      await Future.delayed(const Duration(seconds: 2));
      final started = await BackgroundServiceEnhanced.startEnhancedService();

      setState(() {
        _debugLog +=
            '${DateTime.now()}: Service restart ${started ? 'SUCCESS' : 'FAILED'}\n';
      });

      await _loadDebugInfo();
    } catch (e) {
      setState(() {
        _debugLog += '${DateTime.now()}: ❌ Service restart error: $e\n';
      });
    }
  }

  Future<void> _requestPermissions() async {
    setState(() {
      _debugLog += '${DateTime.now()}: Requesting audio permissions...\n';
    });

    try {
      final granted = await AudioPermissionService.requestAudioPermissions();
      setState(() {
        _debugLog +=
            '${DateTime.now()}: Permission request ${granted ? 'SUCCESS' : 'FAILED'}\n';
      });

      // Reload permission status
      await _loadDebugInfo();

      if (!granted) {
        // Show dialog to open settings
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Permission Required'),
              content: const Text(
                'Audio permissions are required for auto-play azan. Please grant permissions in app settings.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await AudioPermissionService.openSettings();
                  },
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _debugLog += '${DateTime.now()}: ❌ Permission request error: $e\n';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Debug'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12.0), // Reduced padding from 16 to 12
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Cards
            Row(
              children: [
                Expanded(
                  child: Card(
                    color: _autoPlayEnabled
                        ? Colors.green.shade100
                        : Colors.red.shade100,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        children: [
                          Icon(
                            _autoPlayEnabled
                                ? Icons.volume_up
                                : Icons.volume_off,
                            color: _autoPlayEnabled ? Colors.green : Colors.red,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Auto-Play',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _autoPlayEnabled
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          ),
                          Text(
                            _autoPlayEnabled ? 'ENABLED' : 'DISABLED',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Card(
                    color: _serviceRunning
                        ? Colors.blue.shade100
                        : Colors.orange.shade100,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        children: [
                          Icon(
                            _serviceRunning
                                ? Icons.play_circle
                                : Icons.pause_circle,
                            color: _serviceRunning
                                ? Colors.blue
                                : Colors.orange,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Service',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _serviceRunning
                                  ? Colors.blue
                                  : Colors.orange,
                            ),
                          ),
                          Text(
                            _serviceRunning ? 'RUNNING' : 'STOPPED',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Permission Status Card
            Card(
              color: _audioPermissions['canPlayAudio']!
                  ? Colors.green.shade100
                  : Colors.red.shade100,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Icon(
                      _audioPermissions['canPlayAudio']!
                          ? Icons.security
                          : Icons.warning,
                      color: _audioPermissions['canPlayAudio']!
                          ? Colors.green
                          : Colors.red,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Audio Permissions',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _audioPermissions['canPlayAudio']!
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          ),
                          Text(
                            '🎤 Microphone: ${_audioPermissions['microphone']! ? "✅ Granted" : "❌ Denied"}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            '🔔 Notification: ${_audioPermissions['notification']! ? "✅ Granted" : "❌ Denied"}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    if (!_audioPermissions['canPlayAudio']!)
                      ElevatedButton(
                        onPressed: _requestPermissions,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Fix'),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12), // Reduced from 16 to 12
            // Prayer Times Section
            const Text(
              'Prayer Times Today:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6), // Reduced from 8 to 6

            ..._prayerTimes.entries.map((entry) {
              final prayerName = entry.key;
              final timeString = entry.value;
              final audioPlayed = _audioPlayedFlags[prayerName] ?? false;

              return Card(
                child: ListTile(
                  leading: Icon(
                    audioPlayed
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: audioPlayed ? Colors.green : Colors.grey,
                  ),
                  title: Text(prayerName),
                  subtitle: Text(timeString),
                  trailing: ElevatedButton(
                    onPressed: () => _testAudioPlay(prayerName),
                    child: const Text('Test'),
                  ),
                ),
              );
            }),

            const SizedBox(height: 12), // Reduced from 16 to 12
            // Control Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _toggleAutoPlay,
                    icon: Icon(
                      _autoPlayEnabled ? Icons.volume_off : Icons.volume_up,
                    ),
                    label: Text(
                      _autoPlayEnabled
                          ? 'Disable Auto-Play'
                          : 'Enable Auto-Play',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _autoPlayEnabled
                          ? Colors.red
                          : Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _resetAudioFlags,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reset Flags'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            ElevatedButton.icon(
              onPressed: _restartService,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Restart Background Service'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 40),
              ),
            ),

            const SizedBox(height: 12), // Reduced from 16 to 12
            // Debug Log
            const Text(
              'Debug Log:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6), // Reduced from 8 to 6

            Container(
              height: 150, // Reduced from 200 to 150 for better screen fit
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: Text(
                  _debugLog.isEmpty ? 'No debug logs yet...' : _debugLog,
                  style: const TextStyle(
                    color: Colors.green,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _debugLog = '';
                });
              },
              icon: const Icon(Icons.clear),
              label: const Text('Clear Log'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 40),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
