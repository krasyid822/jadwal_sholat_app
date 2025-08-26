import 'package:flutter/material.dart';
import 'package:jadwal_sholat_app/services/notification_service.dart';

class TimeCalibrationScreen extends StatefulWidget {
  const TimeCalibrationScreen({super.key});

  @override
  State<TimeCalibrationScreen> createState() => _TimeCalibrationScreenState();
}

class _TimeCalibrationScreenState extends State<TimeCalibrationScreen> {
  final Map<String, int> _timeOffsets = {};
  int _dayOffset = 0;
  bool _isLoading = true;

  final List<Map<String, dynamic>> _prayerTimes = [
    {'name': 'Subuh', 'key': 'subuh', 'icon': Icons.wb_twilight},
    {'name': 'Dzuhur', 'key': 'dzuhur', 'icon': Icons.wb_sunny},
    {'name': 'Ashar', 'key': 'ashar', 'icon': Icons.wb_cloudy_outlined},
    {'name': 'Maghrib', 'key': 'maghrib', 'icon': Icons.brightness_6},
    {'name': 'Isya', 'key': 'isya', 'icon': Icons.nights_stay_outlined},
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      // Load offset untuk setiap waktu sholat
      for (final prayer in _prayerTimes) {
        final offset = await NotificationService.getTimeOffset(prayer['name']);
        _timeOffsets[prayer['key']] = offset;
      }

      // Load offset hari
      _dayOffset = await NotificationService.getDayOffset();
    } catch (e) {
      debugPrint('Error loading time calibration settings: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveTimeOffset(
    String prayerKey,
    String prayerName,
    int offset,
  ) async {
    try {
      await NotificationService.saveTimeOffset(prayerName, offset);
      setState(() {
        _timeOffsets[prayerKey] = offset;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Offset waktu $prayerName disimpan: ${offset > 0 ? '+' : ''}$offset menit',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error menyimpan offset: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveDayOffset(int offset) async {
    try {
      await NotificationService.saveDayOffset(offset);
      setState(() {
        _dayOffset = offset;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Offset hari disimpan: ${offset > 0 ? '+' : ''}$offset hari',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error menyimpan offset hari: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showTimeOffsetDialog(String prayerKey, String prayerName) {
    final currentOffset = _timeOffsets[prayerKey] ?? 0;
    final controller = TextEditingController(text: currentOffset.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Kalibrasi Waktu $prayerName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Setel offset waktu untuk $prayerName',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '• Gunakan angka positif (+) untuk mempercepat\n'
              '• Gunakan angka negatif (-) untuk memperlambat\n'
              '• Rentang: -30 sampai +30 menit',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              decoration: const InputDecoration(
                labelText: 'Offset (menit)',
                hintText: 'Contoh: +2, -5, 0',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.access_time),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final offsetText = controller.text.trim();
              final offset = int.tryParse(offsetText);

              if (offset != null && offset >= -30 && offset <= 30) {
                Navigator.pop(context);
                await _saveTimeOffset(prayerKey, prayerName, offset);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Masukkan angka antara -30 sampai +30'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _showDayOffsetDialog() {
    final controller = TextEditingController(text: _dayOffset.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Offset Hari'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Setel offset hari untuk perhitungan jadwal',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              '• Gunakan angka positif (+) untuk hari ke depan\n'
              '• Gunakan angka negatif (-) untuk hari sebelumnya\n'
              '• Rentang: -7 sampai +7 hari',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              decoration: const InputDecoration(
                labelText: 'Offset (hari)',
                hintText: 'Contoh: +1, -1, 0',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.calendar_today),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final offsetText = controller.text.trim();
              final offset = int.tryParse(offsetText);

              if (offset != null && offset >= -7 && offset <= 7) {
                Navigator.pop(context);
                await _saveDayOffset(offset);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Masukkan angka antara -7 sampai +7'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _resetAllOffsets() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Semua Kalibrasi'),
        content: const Text(
          'Apakah Anda yakin ingin mengembalikan semua kalibrasi waktu ke pengaturan default (0)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);

              // Reset semua offset waktu sholat
              for (final prayer in _prayerTimes) {
                await _saveTimeOffset(prayer['key'], prayer['name'], 0);
              }

              // Reset offset hari
              await _saveDayOffset(0);

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Semua kalibrasi telah direset ke default'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Kalibrasi Waktu')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kalibrasi Waktu'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _resetAllOffsets,
            tooltip: 'Reset Semua',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header info
          Card(
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
                        'Kalibrasi Waktu Sholat',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sesuaikan waktu sholat dengan kondisi lokal Anda. '
                    'Offset positif akan mempercepat waktu, negatif akan memperlambat.',
                    style: TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Offset hari
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.orange,
                child: Icon(Icons.calendar_today, color: Colors.white),
              ),
              title: const Text('Offset Hari'),
              subtitle: Text(
                _dayOffset == 0
                    ? 'Tidak ada offset'
                    : 'Offset: ${_dayOffset > 0 ? '+' : ''}$_dayOffset hari',
              ),
              trailing: const Icon(Icons.edit),
              onTap: _showDayOffsetDialog,
            ),
          ),

          const SizedBox(height: 8),

          // Daftar waktu sholat
          ...(_prayerTimes.map((prayer) {
            final offset = _timeOffsets[prayer['key']] ?? 0;
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).primaryColor,
                  child: Icon(prayer['icon'], color: Colors.white),
                ),
                title: Text(prayer['name']),
                subtitle: Text(
                  offset == 0
                      ? 'Tidak ada offset'
                      : 'Offset: ${offset > 0 ? '+' : ''}$offset menit',
                ),
                trailing: const Icon(Icons.edit),
                onTap: () =>
                    _showTimeOffsetDialog(prayer['key'], prayer['name']),
              ),
            );
          }).toList()),
        ],
      ),
    );
  }
}
