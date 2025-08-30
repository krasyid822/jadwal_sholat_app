import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import '../utils/prayer_calculation_utils.dart';
import 'package:adhan/adhan.dart' show Coordinates, DateComponents;

/// Compute prayer times and store them in SharedPreferences for the native
/// App Widget to read. This keeps the widget update path simple and robust.
Future<void> updatePrayerTimesForWidget({
  double? fallbackLat,
  double? fallbackLng,
}) async {
  final prefs = await SharedPreferences.getInstance();
  try {
    Position pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      );
    } catch (_) {
      // fallback to provided coordinates or a sensible default (Jakarta)
      pos = Position(
        longitude: fallbackLng ?? 106.827153,
        latitude: fallbackLat ?? -6.175110,
        timestamp: DateTime.now(),
        accuracy: 100.0,
        altitude: 0.0,
        heading: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
        headingAccuracy: 0.0,
        altitudeAccuracy: 0.0,
      );
    }

    Coordinates coords;
    try {
      coords = Coordinates(pos.latitude, pos.longitude);
    } catch (_) {
      coords = Coordinates(fallbackLat ?? -6.175110, fallbackLng ?? 106.827153);
    }

    final date = DateComponents.from(DateTime.now());
    final prayerTimes =
        await PrayerCalculationUtils.calculatePrayerTimesEnhanced(
          coords,
          date,
          useCache: false,
        );

    final fmt = DateFormat.Hm();
    await prefs.setString(
      'widget_location',
      '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}',
    );
    await prefs.setString('widget_subuh', fmt.format(prayerTimes.fajr));
    await prefs.setString('widget_dzuhur', fmt.format(prayerTimes.dhuhr));
    await prefs.setString('widget_ashar', fmt.format(prayerTimes.asr));
    await prefs.setString('widget_maghrib', fmt.format(prayerTimes.maghrib));
    await prefs.setString('widget_isya', fmt.format(prayerTimes.isha));
    await prefs.setInt(
      'widget_last_update_ms',
      DateTime.now().millisecondsSinceEpoch,
    );
  } catch (e) {
    // On any error, ensure widget has safe placeholder values.
    await prefs.setString('widget_location', 'Lokasi tidak tersedia');
    await prefs.setString('widget_subuh', '--:--');
    await prefs.setString('widget_dzuhur', '--:--');
    await prefs.setString('widget_ashar', '--:--');
    await prefs.setString('widget_maghrib', '--:--');
    await prefs.setString('widget_isya', '--:--');
    await prefs.setInt(
      'widget_last_update_ms',
      DateTime.now().millisecondsSinceEpoch,
    );
  }
}

// Headless entrypoint invoked by a native headless FlutterEngine.
// The worker will start a FlutterEngine, execute this entrypoint and wait
// for the Dart code to call the native-side MethodChannel back when done.
@pragma('vm:entry-point')
Future<void> backgroundUpdatePrayerTimesEntrypoint() async {
  // Ensure bindings are initialized for background execution (isolates)
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await updatePrayerTimesForWidget();
    const MethodChannel(
      'jadwalsholat.rasyid/widget_update',
    ).invokeMethod('updateComplete');
  } catch (e) {
    // Notify native side of failure (optional payload)
    try {
      const MethodChannel(
        'jadwalsholat.rasyid/widget_update',
      ).invokeMethod('updateFailed', e.toString());
    } catch (_) {}
    rethrow;
  }
}
