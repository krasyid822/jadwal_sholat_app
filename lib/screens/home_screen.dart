import 'dart:async';
import 'package:flutter/material.dart';
import 'package:jadwal_sholat_app/utils/prayer_time_formatter.dart';
import 'package:jadwal_sholat_app/utils/prayer_calculation_utils.dart';
import 'package:adhan/adhan.dart';
import 'package:geocoding/geocoding.dart' show placemarkFromCoordinates, Placemark;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:jadwal_sholat_app/screens/monthly_schedule_screen.dart';
import 'package:jadwal_sholat_app/screens/qibla_screen.dart';
import 'package:jadwal_sholat_app/screens/settings_screen_enhanced.dart';
import 'package:jadwal_sholat_app/services/location_service.dart';
import 'package:jadwal_sholat_app/services/notification_service_enhanced.dart';
import 'package:jadwal_sholat_app/utils/route_observer.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RouteAware {
  PrayerTimes? _prayerTimes;
  Placemark? _placemark;
  Position? _position;
  bool _isLoading = true;
  String _errorMessage = '';
  Timer? _timer;
  String _countdown = '00:00:00';
  String _nextPrayer = 'Memuat...';

  @override
  void initState() {
    super.initState();
    _loadPrayerTimes();
    // check after first frame if adhan audio is playing
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowStopAdhanDialog());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    appRouteObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didPopNext() {
    // Called when returning to this route (e.g., from Settings). Re-check audio state.
    _maybeShowStopAdhanDialog();
  }

  Future<void> _loadPrayerTimes() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final position = await LocationService.determinePosition();
      List<Placemark> placemarks = [];
      if (!kIsWeb) {
        try {
          placemarks = await placemarkFromCoordinates(
            position.latitude,
            position.longitude,
          );
        } catch (e) {
          debugPrint('Geocoding failed on native platform: $e');
          placemarks = [];
        }
      } else {
        // On web, geocoding via plugin may be unsupported. Leave placemarks empty
        // so UI can fall back to coordinates or cached place name.
        debugPrint('Skipping placemarkFromCoordinates on web');
      }

      final myCoordinates = Coordinates(position.latitude, position.longitude);

      // Gunakan PrayerCalculationUtils yang sudah diperbaiki dengan elevasi akurat
      final cityName = placemarks.isNotEmpty ? placemarks[0].locality : null;
      final prayerTimes =
          await PrayerCalculationUtils.calculatePrayerTimesEnhanced(
            myCoordinates,
            DateComponents.from(DateTime.now()),
            cityName: cityName,
          );

      setState(() {
        _position = position;
        _placemark = placemarks.isNotEmpty ? placemarks[0] : null;
        _prayerTimes = prayerTimes;
        _isLoading = false;
      });

      // Save simple values for the Android launcher widget to read via platform prefs
      try {
        final prefs = await SharedPreferences.getInstance();
        final placeName = _placemark != null
            ? (_placemark!.subLocality?.isNotEmpty == true ? _placemark!.subLocality : _placemark!.locality)
            : 'Lokasi tidak diketahui';
        await prefs.setString('last_place_name', placeName ?? 'Lokasi tidak diketahui');
        // next prayer info
        final nextPrayerEnum = _prayerTimes!.nextPrayer();
        final nextPrayerName = _prayerName(nextPrayerEnum);
        final nextPrayerTime = _prayerTimes!.timeForPrayer(nextPrayerEnum);
        if (nextPrayerTime != null) {
          await prefs.setString('next_prayer_name', nextPrayerName);
          await prefs.setString('next_prayer_time', DateTime.now().isUtc ? nextPrayerTime.toIso8601String() : nextPrayerTime.toString().substring(11,16));
        }
      } catch (_) {
        // ignore prefs errors for widget
      }

      _startTimer();
      // Menjadwalkan notifikasi harian setelah waktu sholat berhasil didapatkan
      if (_prayerTimes != null) {
        NotificationServiceEnhanced.scheduleEnhancedDailyNotifications(
          _prayerTimes!,
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _startTimer() {
    _timer?.cancel(); // Batalkan timer lama jika ada
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _prayerTimes == null) {
        timer.cancel();
        return;
      }

      DateTime now = DateTime.now();
      Prayer nextPrayerEnum = _prayerTimes!.nextPrayer();
      DateTime nextPrayerTime;

      // Menentukan waktu sholat berikutnya, handle jika sudah melewati Isya
      if (nextPrayerEnum == Prayer.none) {
        // Ambil jadwal sholat untuk besok
        final tomorrow = DateTime.now().add(const Duration(days: 1));
        final tomorrowPrayerTimes = PrayerTimes(
          _prayerTimes!.coordinates,
          DateComponents.from(tomorrow),
          _prayerTimes!.calculationParameters,
        );
        nextPrayerTime = tomorrowPrayerTimes.fajr;
        nextPrayerEnum = Prayer.fajr;
      } else {
        nextPrayerTime = _prayerTimes!.timeForPrayer(nextPrayerEnum)!;
      }

      if (nextPrayerTime.isBefore(now)) {
        // Jika waktu sholat berikutnya sudah lewat, muat ulang jadwal
        _loadPrayerTimes();
        return;
      }

      final difference = nextPrayerTime.difference(now);

      setState(() {
        _countdown = _formatDuration(difference);
        _nextPrayer = _prayerName(nextPrayerEnum);
      });
    });
  }

  // Fungsi untuk memformat durasi menjadi HH:MM:SS
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String hours = twoDigits(duration.inHours);
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }

  // Fungsi untuk mengubah enum Prayer menjadi nama String
  String _prayerName(Prayer prayer) {
    switch (prayer) {
      case Prayer.fajr:
        return 'Subuh';
      case Prayer.sunrise:
        return 'Terbit';
      case Prayer.dhuhr:
        return 'Dzuhur';
      case Prayer.asr:
        return 'Ashar';
      case Prayer.maghrib:
        return 'Maghrib';
      case Prayer.isha:
        return 'Isya';
      default:
        return 'Subuh Berikutnya';
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jadwal Sholat'),
        actions: [
          IconButton(
            tooltip: 'Jadwal Bulanan',
            icon: const Icon(Icons.calendar_month),
            onPressed: _prayerTimes == null
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MonthlyScheduleScreen(
                        coordinates: _prayerTimes!.coordinates,
                      ),
                    ),
                  ),
          ),
          IconButton(
            tooltip: 'Arah Kiblat',
            icon: const Icon(Icons.explore_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const QiblaScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Pengaturan',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Error: $_errorMessage\n\nSilakan coba lagi.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadPrayerTimes,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildLocationInfo(),
                  const SizedBox(height: 20),
                  _buildCountdownCard(),
                  const SizedBox(height: 20),
                  _buildSectionHeader('5 Waktu Sholat Wajib'),
                  _buildPrayerTimeItem(
                    'Subuh',
                    _prayerTimes!.fajr,
                    Icons.wb_twilight,
                  ),
                  _buildPrayerTimeItem(
                    'Dzuhur',
                    _prayerTimes!.dhuhr,
                    Icons.wb_sunny,
                  ),
                  _buildPrayerTimeItem(
                    'Ashar',
                    _prayerTimes!.asr,
                    Icons.wb_cloudy_outlined,
                  ),
                  _buildPrayerTimeItem(
                    'Maghrib',
                    _prayerTimes!.maghrib,
                    Icons.brightness_6,
                  ),
                  _buildPrayerTimeItem(
                    'Isya',
                    _prayerTimes!.isha,
                    Icons.nights_stay_outlined,
                  ),
                  const SizedBox(height: 12),
                  _buildSectionHeader('Waktu Lainnya'),
                  _buildPrayerTimeItem(
                    'Imsak',
                    _prayerTimes!.fajr.subtract(const Duration(minutes: 10)),
                    Icons.timer_outlined,
                  ),
                  _buildPrayerTimeItem(
                    'Terbit',
                    _prayerTimes!.sunrise,
                    Icons.wb_sunny_outlined,
                  ),
                  _buildPrayerTimeItem(
                    'Dhuha',
                    PrayerCalculationUtils.calculateDhuha(
                      _prayerTimes!.sunrise,
                    ),
                    Icons.wb_sunny,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildLocationInfo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              _formatLocationDisplay(),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Lat: ${_position?.latitude.toStringAsFixed(4) ?? 'N/A'}, Lon: ${_position?.longitude.toStringAsFixed(4) ?? 'N/A'}',
              style: TextStyle(fontSize: 14, color: Colors.grey[400]),
            ),
            Text(
              'Elevasi: ${_position?.altitude.toStringAsFixed(2) ?? 'N/A'} mdpl',
              style: TextStyle(fontSize: 14, color: Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }

  String _formatLocationDisplay() {
    // Prefer human-readable placemark parts when available
    if (_placemark != null) {
      final parts = <String>[];
      if ((_placemark!.subLocality ?? '').isNotEmpty) parts.add(_placemark!.subLocality!);
      if ((_placemark!.locality ?? '').isNotEmpty && !parts.contains(_placemark!.locality)) parts.add(_placemark!.locality!);
      if ((_placemark!.subAdministrativeArea ?? '').isNotEmpty && !parts.contains(_placemark!.subAdministrativeArea)) parts.add(_placemark!.subAdministrativeArea!);
      if ((_placemark!.administrativeArea ?? '').isNotEmpty && !parts.contains(_placemark!.administrativeArea)) parts.add(_placemark!.administrativeArea!);
      if ((_placemark!.country ?? '').isNotEmpty) parts.add(_placemark!.country!);

      if (parts.isNotEmpty) return parts.join(', ');
    }

    // If no placemark, fall back to coordinates if available
    if (_position != null) {
      return 'Koordinat ${_position!.latitude.toStringAsFixed(4)}, ${_position!.longitude.toStringAsFixed(4)}';
    }

    // Final fallback
    return 'Lokasi tidak diketahui';
  }

  Future<void> _maybeShowStopAdhanDialog() async {
    try {
      final isPlaying = await NotificationServiceEnhanced.isAdhanPlaying();
      if (!isPlaying) return;

      // If there's already a dialog open, don't open another
      if (!mounted) return;

      final stop = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: const Text('Audio Azan Sedang Diputar'),
            content: const Text('Apakah Anda ingin menghentikan audio azan yang sedang diputar?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Biarkan'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Hentikan'),
              ),
            ],
          );
        },
      );

      if (stop == true) {
        await NotificationServiceEnhanced.stopAdhanAudio();
      }
    } catch (e) {
      // ignore errors silently
    }
  }

  Widget _buildCountdownCard() {
    return Card(
      color: Theme.of(context).primaryColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24.0),
        child: Column(
          children: [
            Text(
              'Menuju Waktu $_nextPrayer',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _countdown,
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrayerTimeItem(String name, DateTime time, IconData icon) {
    bool isNextPrayer = name == _nextPrayer;
    return Card(
      color: isNextPrayer
          ? Theme.of(context).primaryColor.withValues(alpha: 0.3)
          : Theme.of(context).cardColor,
      child: ListTile(
        leading: Icon(
          icon,
          color: isNextPrayer
              ? Colors.tealAccent
              : Theme.of(context).colorScheme.secondary,
        ),
        title: Text(
          name,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
        trailing: Text(
          PrayerTimeFormatter.formatTimeForContext(context, time),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isNextPrayer ? Colors.tealAccent : Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4.0, right: 4.0),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Divider(
              height: 1,
              thickness: 1,
              color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}
