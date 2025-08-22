import 'package:flutter/material.dart';
import 'package:adhan/adhan.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart'; // <-- PERBAIKAN DI BARIS INI
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// Inisialisasi plugin notifikasi
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  // Pastikan binding Flutter sudah siap
  WidgetsFlutterBinding.ensureInitialized();

  // Inisialisasi database timezone
  tz.initializeTimeZones();

  // Pengaturan awal untuk notifikasi
  await setupNotifications();

  runApp(const JadwalSholatApp());
}

// Fungsi untuk inisialisasi notifikasi
Future<void> setupNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
}

class JadwalSholatApp extends StatelessWidget {
  const JadwalSholatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Jadwal Sholat Offline',
      theme: ThemeData(
        primarySwatch: Colors.teal,
        brightness: Brightness.dark,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  PrayerTimes? _prayerTimes;
  String _locationMessage = "Mencari lokasi...";
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPrayerTimes();
  }

  Future<void> _loadPrayerTimes() async {
    setState(() {
      _isLoading = true;
    });

    try {
      Position position = await _determinePosition();
      final myCoordinates = Coordinates(position.latitude, position.longitude);
      final params = CalculationMethod.singapore.getParameters();
      params.madhab = Madhab.shafi;

      setState(() {
        _prayerTimes = PrayerTimes.today(myCoordinates, params);
        _locationMessage = "Jadwal Sholat Hari Ini";
        _isLoading = false;
      });

      // Setelah jadwal didapatkan, atur notifikasinya
      _scheduleAllNotifications(_prayerTimes!);
    } catch (e) {
      setState(() {
        _locationMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  // Fungsi untuk menjadwalkan semua notifikasi
  Future<void> _scheduleAllNotifications(PrayerTimes prayerTimes) async {
    // Batalkan notifikasi lama agar tidak tumpang tindih
    await flutterLocalNotificationsPlugin.cancelAll();

    _schedulePrayerTimeNotification('Subuh', prayerTimes.fajr);
    _schedulePrayerTimeNotification('Dzuhur', prayerTimes.dhuhr);
    _schedulePrayerTimeNotification('Ashar', prayerTimes.asr);
    _schedulePrayerTimeNotification('Maghrib', prayerTimes.maghrib);
    _schedulePrayerTimeNotification('Isya', prayerTimes.isha);
  }

  // Fungsi untuk menjadwalkan satu notifikasi
  Future<void> _schedulePrayerTimeNotification(
      String prayerName, DateTime prayerTime) async {
    // Pastikan waktu notifikasi belum lewat
    if (prayerTime.isBefore(DateTime.now())) {
      return;
    }

    final tz.TZDateTime scheduledDate = tz.TZDateTime.from(prayerTime, tz.local);

    await flutterLocalNotificationsPlugin.zonedSchedule(
      prayerName.hashCode,
      'Waktunya Sholat',
      'Segera laksanakan sholat $prayerName',
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'prayer_time_channel_id',
          'Prayer Time Notifications',
          channelDescription: 'Notifikasi pengingat waktu sholat',
          importance: Importance.max,
          priority: Priority.high,
          sound: RawResourceAndroidNotificationSound('adzan'), // Ganti 'adzan' jika punya file suara
          icon: '@mipmap/ic_launcher',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_locationMessage),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPrayerTimes,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _prayerTimes == null
              ? Center(child: Text("Gagal memuat jadwal: $_locationMessage"))
              : ListView(
                  padding: const EdgeInsets.all(12.0),
                  children: [
                    _buildPrayerTimeCard('Subuh', _prayerTimes!.fajr, Icons.brightness_4),
                    _buildPrayerTimeCard('Terbit', _prayerTimes!.sunrise, Icons.wb_sunny_outlined),
                    _buildPrayerTimeCard('Dzuhur', _prayerTimes!.dhuhr, Icons.wb_sunny),
                    _buildPrayerTimeCard('Ashar', _prayerTimes!.asr, Icons.wb_cloudy),
                    _buildPrayerTimeCard('Maghrib', _prayerTimes!.maghrib, Icons.brightness_6),
                    _buildPrayerTimeCard('Isya', _prayerTimes!.isha, Icons.nights_stay),
                  ],
                ),
    );
  }

  Widget _buildPrayerTimeCard(String name, DateTime time, IconData icon) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(icon, size: 30, color: Theme.of(context).colorScheme.secondary),
            const SizedBox(width: 20),
            Text(name, style: const TextStyle(fontSize: 20)),
            const Spacer(),
            Text(
              DateFormat.jm().format(time),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Layanan lokasi dimatikan.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Izin lokasi ditolak.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error(
          'Izin lokasi ditolak permanen, aplikasi tidak bisa meminta izin.');
    }

    return await Geolocator.getCurrentPosition();
  }
}