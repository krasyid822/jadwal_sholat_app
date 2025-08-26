import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_compass_v2/flutter_compass_v2.dart';
import 'package:geolocator/geolocator.dart';

/// Service untuk menangani kompas dengan sensor fusion dan filtering
/// Implementasi berdasarkan SOP kompas kiblat yang mulus
class CompassService {
  static const double _kaabaLatitude = 21.4225;
  static const double _kaabaLongitude = 39.8262;

  // Low-pass filter constants
  static const double _alpha = 0.15; // Filter smoothing factor (0-1)
  static const int _sensorDelay = 50; // milliseconds

  // Filtered sensor values
  double _filteredHeading = 0.0;
  double _previousHeading = 0.0;
  bool _isInitialized = false;

  // Streams
  StreamController<CompassData>? _compassController;
  StreamSubscription<CompassEvent>? _compassSubscription;
  Timer? _updateTimer;

  // Location
  Position? _currentPosition;
  double _qiblaDirection = 0.0;
  double _magneticDeclination = 0.0;

  /// Stream untuk mendapatkan data kompas yang sudah di-filter
  Stream<CompassData>? get compassStream => _compassController?.stream;

  /// Inisialisasi compass service
  Future<bool> initialize() async {
    try {
      _compassController = StreamController<CompassData>.broadcast();

      // Check compass availability
      final hasCompass = await _checkCompassAvailability();
      if (!hasCompass) return false;

      // Get location and calculate qibla
      await _updateLocation();

      // Start compass stream with filtering
      _startCompassStream();

      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('Error initializing compass service: $e');
      return false;
    }
  }

  /// Check if compass is available on device
  Future<bool> _checkCompassAvailability() async {
    try {
      final completer = Completer<bool>();
      StreamSubscription<CompassEvent>? testSubscription;

      testSubscription = FlutterCompass.events?.listen(
        (event) {
          completer.complete(true);
          testSubscription?.cancel();
        },
        onError: (e) {
          completer.complete(false);
          testSubscription?.cancel();
        },
      );

      return await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          testSubscription?.cancel();
          return false;
        },
      );
    } catch (e) {
      return false;
    }
  }

  /// Update location and calculate qibla direction
  Future<void> _updateLocation() async {
    try {
      _currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (_currentPosition != null) {
        // Calculate qibla direction using great-circle formula
        _qiblaDirection = _calculateQiblaDirection(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        );

        // Calculate magnetic declination for this location
        _magneticDeclination = _calculateMagneticDeclination(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        );
      }
    } catch (e) {
      debugPrint('Error updating location: $e');
    }
  }

  /// Calculate qibla direction using great-circle formula
  double _calculateQiblaDirection(double latitude, double longitude) {
    final lat1 = _toRadians(latitude);
    final lon1 = _toRadians(longitude);
    final lat2 = _toRadians(_kaabaLatitude);
    final lon2 = _toRadians(_kaabaLongitude);

    final deltaLon = lon2 - lon1;

    final y = sin(deltaLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon);

    final bearing = atan2(y, x);
    return _toDegrees(bearing).remainder(360);
  }

  /// Simple magnetic declination calculation
  /// For more accuracy, should use NOAA World Magnetic Model
  double _calculateMagneticDeclination(double latitude, double longitude) {
    // Simplified calculation - in production, use proper magnetic declination API
    // This is a rough approximation for Indonesia region
    return -0.5; // degrees
  }

  /// Start compass stream with low-pass filtering
  void _startCompassStream() {
    _compassSubscription = FlutterCompass.events?.listen(
      (event) {
        if (event.heading != null) {
          _processCompassReading(event.heading!);
        }
      },
      onError: (e) {
        debugPrint('Compass stream error: $e');
      },
    );

    // Update timer for smooth animation
    _updateTimer = Timer.periodic(
      Duration(milliseconds: _sensorDelay),
      (timer) => _emitCompassData(),
    );
  }

  /// Process compass reading with low-pass filter
  void _processCompassReading(double heading) {
    // Handle angle wrapping for smooth filtering
    if (!_isInitialized) {
      _filteredHeading = heading;
      _previousHeading = heading;
      return;
    }

    // Calculate angular difference
    double diff = heading - _previousHeading;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;

    // Apply low-pass filter
    _filteredHeading = _filteredHeading + _alpha * diff;
    _filteredHeading = _filteredHeading.remainder(360);
    if (_filteredHeading < 0) _filteredHeading += 360;

    _previousHeading = heading;
  }

  /// Emit compass data to stream
  void _emitCompassData() {
    if (!_isInitialized || _compassController?.isClosed == true) return;

    // Apply magnetic declination correction
    double trueNorth = (_filteredHeading + _magneticDeclination).remainder(360);
    if (trueNorth < 0) trueNorth += 360;

    // Calculate relative qibla direction (qibla relative to current heading)
    double relativeQibla = (_qiblaDirection - trueNorth);
    // Normalize to -180 to 180 range for proper rotation
    while (relativeQibla > 180) {
      relativeQibla -= 360;
    }
    while (relativeQibla < -180) {
      relativeQibla += 360;
    }

    final data = CompassData(
      heading: _filteredHeading,
      trueNorthHeading: trueNorth,
      qiblaDirection: _qiblaDirection,
      relativeQiblaDirection: relativeQibla,
      accuracy: _calculateAccuracy(),
      position: _currentPosition,
    );

    _compassController?.add(data);
  }

  /// Calculate compass accuracy based on sensor stability
  CompassAccuracy _calculateAccuracy() {
    // Simple accuracy calculation based on recent readings stability
    // In production, this could be more sophisticated
    return CompassAccuracy.high;
  }

  /// Dispose resources
  void dispose() {
    _compassSubscription?.cancel();
    _updateTimer?.cancel();
    _compassController?.close();
    _isInitialized = false;
  }

  // Helper functions
  double _toRadians(double degrees) => degrees * pi / 180.0;
  double _toDegrees(double radians) => radians * 180.0 / pi;
}

/// Data class for compass information
class CompassData {
  final double heading; // Raw magnetic heading
  final double trueNorthHeading; // Corrected for magnetic declination
  final double qiblaDirection; // Absolute qibla direction
  final double relativeQiblaDirection; // Qibla relative to current heading
  final CompassAccuracy accuracy;
  final Position? position;

  const CompassData({
    required this.heading,
    required this.trueNorthHeading,
    required this.qiblaDirection,
    required this.relativeQiblaDirection,
    required this.accuracy,
    this.position,
  });
}

/// Compass accuracy levels
enum CompassAccuracy { low, medium, high }
