import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:jadwal_sholat_app/screens/time_calibration_screen.dart';
import 'package:jadwal_sholat_app/screens/report_issue_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isAutoRefreshEnabled = false;
  bool _isCountdownNotificationEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  // Memuat pengaturan yang tersimpan dari SharedPreferences
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isAutoRefreshEnabled = prefs.getBool('auto_location_refresh') ?? true;
      _isCountdownNotificationEnabled =
          prefs.getBool('countdown_notifications') ?? true;
    });
  }

  // Menyimpan pengaturan refresh otomatis
  void _setAutoRefresh(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_location_refresh', value);
    setState(() {
      _isAutoRefreshEnabled = value;
    });

    // Implementasi logika untuk memulai atau menghentikan background service
    try {
      final service = FlutterBackgroundService();
      if (value) {
        await service.startService();
      } else {
        service.invoke('stopService');
      }
    } catch (e) {
      // Handle error jika service tidak tersedia
      debugPrint('Error managing background service: $e');
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Refresh otomatis ${value ? "diaktifkan" : "dimatikan"}',
          ),
        ),
      );
    }
  }

  // Menyimpan pengaturan notifikasi countdown
  void _setCountdownNotification(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('countdown_notifications', value);
    setState(() {
      _isCountdownNotificationEnabled = value;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Notifikasi countdown ${value ? "diaktifkan" : "dimatikan"}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        children: [
          _buildSectionHeader('Notifikasi'),
          SwitchListTile(
            title: const Text('Notifikasi Countdown'),
            subtitle: const Text('Pengingat 10 menit sebelum waktu sholat'),
            value: _isCountdownNotificationEnabled,
            onChanged: _setCountdownNotification,
          ),

          const Divider(),
          _buildSectionHeader('Lokasi & Kalkulasi'),
          SwitchListTile(
            title: const Text('Refresh Lokasi Otomatis'),
            subtitle: const Text(
              'Update lokasi & jadwal di latar belakang setiap jam',
            ),
            value: _isAutoRefreshEnabled,
            onChanged: _setAutoRefresh,
          ),
          ListTile(
            title: const Text('Kalibrasi Waktu'),
            subtitle: const Text(
              'Setel offset waktu untuk setiap sholat dan hari',
            ),
            trailing: const Icon(Icons.timer_outlined),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TimeCalibrationScreen(),
                ),
              );
            },
          ),

          const Divider(),
          _buildSectionHeader('Lainnya'),
          ListTile(
            title: const Text('Lapor Isu'),
            subtitle: const Text('Laporkan bug atau beri masukan di GitHub'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ReportIssueScreen(),
                ),
              );
            },
          ),

          const SizedBox(height: 20),

          // Info aplikasi
          Card(
            margin: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade600),
                      const SizedBox(width: 8),
                      Text(
                        'Tentang Aplikasi',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '• Aplikasi ini menggunakan perhitungan standar Kementerian Agama RI\n'
                    '• Notifikasi countdown akan menampilkan hitungan mundur di panel notifikasi\n'
                    '• Lokasi akan di-cache untuk menghemat penggunaan GPS\n'
                    '• Refresh otomatis berjalan setiap jam untuk memperbarui lokasi',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.secondary,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
