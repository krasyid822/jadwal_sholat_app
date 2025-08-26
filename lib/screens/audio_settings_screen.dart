import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jadwal_sholat_app/services/notification_service_enhanced.dart';

class AudioSettingsScreen extends StatefulWidget {
  const AudioSettingsScreen({super.key});

  @override
  State<AudioSettingsScreen> createState() => _AudioSettingsScreenState();
}

class _AudioSettingsScreenState extends State<AudioSettingsScreen> {
  Map<String, String> _prayerAudioSettings = {};
  bool _isLoading = true;

  // Daftar audio yang tersedia
  final Map<String, String> _availableAudio = {
    'azan.mp3': 'Azan Default',
    'azan_subuh.mp3': 'Azan Subuh',
    'default': 'Tidak Ada Suara',
  };

  // Daftar waktu sholat
  final Map<String, String> _prayerTimes = {
    'subuh': 'Subuh',
    'dzuhur': 'Dzuhur',
    'ashar': 'Ashar',
    'maghrib': 'Maghrib',
    'isya': 'Isya',
  };

  @override
  void initState() {
    super.initState();
    _loadAudioSettings();
  }

  Future<void> _loadAudioSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      // Set default audio settings
      _prayerAudioSettings = {
        'subuh': prefs.getString('audio_subuh') ?? 'azan_subuh.mp3',
        'dzuhur': prefs.getString('audio_dzuhur') ?? 'azan.mp3',
        'ashar': prefs.getString('audio_ashar') ?? 'azan.mp3',
        'maghrib': prefs.getString('audio_maghrib') ?? 'azan.mp3',
        'isya': prefs.getString('audio_isya') ?? 'azan.mp3',
      };
      _isLoading = false;
    });
  }

  Future<void> _saveAudioSetting(String prayerTime, String audioFile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('audio_$prayerTime', audioFile);
    setState(() {
      _prayerAudioSettings[prayerTime] = audioFile;
    });
  }

  void _showAudioSelectionDialog(String prayerTime) {
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Pilih Audio untuk ${_prayerTimes[prayerTime]}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: _availableAudio.entries.map((entry) {
              final isSelected = _prayerAudioSettings[prayerTime] == entry.key;
              return ListTile(
                title: Text(entry.value),
                leading: Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: isSelected ? Theme.of(context).primaryColor : null,
                ),
                trailing: isSelected
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () {
                  _saveAudioSetting(prayerTime, entry.key);
                  navigator.pop();
                },
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => navigator.pop(),
              child: const Text('Batal'),
            ),
            if (_prayerAudioSettings[prayerTime] != 'default')
              TextButton(
                onPressed: () async {
                  // Test audio
                  await NotificationServiceEnhanced.showTestNotification();
                  if (!mounted) return;
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(
                      content: Text('Tes audio dikirim!'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                child: const Text('Tes Audio'),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan Audio Azan'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Kustomisasi Suara Azan',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Pilih suara azan yang berbeda untuk setiap waktu sholat.',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _prayerTimes.length,
                      itemBuilder: (context, index) {
                        final prayerTime = _prayerTimes.keys.elementAt(index);
                        final prayerName = _prayerTimes[prayerTime]!;
                        final currentAudio =
                            _prayerAudioSettings[prayerTime] ?? 'azan.mp3';
                        final audioName =
                            _availableAudio[currentAudio] ?? 'Audio Custom';

                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(context).primaryColor,
                              child: Icon(
                                _getPrayerIcon(prayerTime),
                                color: Colors.white,
                              ),
                            ),
                            title: Text(
                              prayerName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              'Audio: $audioName',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                            trailing: const Icon(Icons.edit),
                            onTap: () => _showAudioSelectionDialog(prayerTime),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  Card(
                    color: Colors.blue.shade50,
                    child: const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Audio azan akan diputar saat notifikasi waktu sholat. Pastikan volume perangkat Anda tidak dalam mode silent.',
                              style: TextStyle(color: Colors.blue),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  IconData _getPrayerIcon(String prayerTime) {
    switch (prayerTime) {
      case 'subuh':
        return Icons.wb_twilight;
      case 'dzuhur':
        return Icons.wb_sunny;
      case 'ashar':
        return Icons.wb_cloudy_outlined;
      case 'maghrib':
        return Icons.brightness_6;
      case 'isya':
        return Icons.nights_stay_outlined;
      default:
        return Icons.schedule;
    }
  }
}
