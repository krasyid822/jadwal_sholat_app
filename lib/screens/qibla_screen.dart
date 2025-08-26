import 'package:flutter/material.dart';
import 'package:flutter_compass_v2/flutter_compass_v2.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:math';
import 'dart:async';

/// Screen untuk menampilkan arah kiblat
class QiblaScreen extends StatefulWidget {
  const QiblaScreen({super.key});

  @override
  State<QiblaScreen> createState() => _QiblaScreenState();
}

class _QiblaScreenState extends State<QiblaScreen> {
  bool _isCheckingPermissions = true;
  bool _hasLocationPermission = false;
  bool _hasSensorSupport = false;
  String? _permissionError;

  // Compass and location streams
  StreamSubscription<CompassEvent>? _compassSubscription;
  StreamSubscription<Position>? _positionSubscription;

  double _currentDirection = 0.0;
  double _qiblaDirection = 0.0;
  Position? _currentPosition;
  Timer? _debounceTimer;
  double? _previousDirection;

  // Konstanta Kabah (Makkah)
  static const double _kaabaLatitude = 21.4225;
  static const double _kaabaLongitude = 39.8262;

  // Konfigurasi performa
  static const Duration _debounceDelay = Duration(milliseconds: 100);
  static const double _updateThreshold = 1.0;

  @override
  void initState() {
    super.initState();
    _initializeQibla();
  }

  @override
  void dispose() {
    _compassSubscription?.cancel();
    _positionSubscription?.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeQibla() async {
    try {
      final results = await Future.wait([
        _checkLocationPermission(),
        _checkSensorSupport(),
      ]);

      if (mounted) {
        setState(() {
          _hasLocationPermission = results[0];
          _hasSensorSupport = results[1];
          _isCheckingPermissions = false;
        });

        if (_hasLocationPermission && _hasSensorSupport) {
          _startQiblaCalculation();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _permissionError = 'Gagal memeriksa permission: $e';
          _isCheckingPermissions = false;
        });
      }
    }
  }

  Future<bool> _checkLocationPermission() async {
    try {
      final locationWhenInUse = await Permission.locationWhenInUse.status;
      if (locationWhenInUse.isGranted) return true;

      final result = await Permission.locationWhenInUse.request();
      return result.isGranted;
    } catch (e) {
      debugPrint('Error checking location permission: $e');
      return false;
    }
  }

  Future<bool> _checkSensorSupport() async {
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
      debugPrint('Error checking sensor support: $e');
      return false;
    }
  }

  void _startQiblaCalculation() {
    // Start location stream
    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        ).listen(
          (position) {
            _currentPosition = position;
            _calculateQiblaDirection();
          },
          onError: (e) {
            debugPrint('Location stream error: $e');
          },
        );

    // Start compass stream
    _compassSubscription = FlutterCompass.events?.listen(
      (event) {
        if (event.heading != null) {
          _updateCompassDirection(event.heading!);
        }
      },
      onError: (e) {
        debugPrint('Compass stream error: $e');
      },
    );
  }

  void _calculateQiblaDirection() {
    if (_currentPosition == null) return;

    final qiblaBearing = Geolocator.bearingBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _kaabaLatitude,
      _kaabaLongitude,
    );

    setState(() {
      _qiblaDirection = qiblaBearing < 0 ? qiblaBearing + 360 : qiblaBearing;
    });
  }

  void _updateCompassDirection(double heading) {
    if (_previousDirection == null ||
        (heading - _previousDirection!).abs() > _updateThreshold) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(_debounceDelay, () {
        if (mounted) {
          setState(() {
            _currentDirection = heading < 0 ? heading + 360 : heading;
            _previousDirection = heading;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingPermissions) {
      return Scaffold(
        appBar: AppBar(title: const Text('Arah Kiblat')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Memeriksa permission dan sensor...',
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    if (_permissionError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Arah Kiblat')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _permissionError!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _initializeQibla,
                child: const Text('Coba Lagi'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_hasLocationPermission) {
      return Scaffold(
        appBar: AppBar(title: const Text('Arah Kiblat')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_off, size: 64, color: Colors.orange),
              const SizedBox(height: 16),
              const Text(
                'Permission lokasi diperlukan untuk menentukan arah kiblat',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _initializeQibla,
                child: const Text('Berikan Permission'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_hasSensorSupport) {
      return Scaffold(
        appBar: AppBar(title: const Text('Arah Kiblat')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.explore_off, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Sensor kompas tidak tersedia pada perangkat ini',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    // Main compass display
    return Scaffold(
      appBar: AppBar(
        title: const Text('Arah Kiblat'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.lightBlue, Colors.white],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Info current position
              if (_currentPosition != null) ...[
                Card(
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(
                          'Lokasi Saat Ini',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Lat: ${_currentPosition!.latitude.toStringAsFixed(4)}',
                        ),
                        Text(
                          'Lng: ${_currentPosition!.longitude.toStringAsFixed(4)}',
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // Compass
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: 300,
                    height: 300,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Compass background
                        Container(
                          width: 300,
                          height: 300,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black, width: 2),
                            color: Colors.white,
                          ),
                        ),

                        // North indicator
                        Positioned(
                          top: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'N',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),

                        // Qibla direction needle
                        Transform.rotate(
                          angle:
                              (_qiblaDirection - _currentDirection) * pi / 180,
                          child: Container(
                            width: 4,
                            height: 120,
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),

                        // Center dot
                        Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Direction info
              Card(
                margin: const EdgeInsets.all(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        'Arah Kiblat',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_qiblaDirection.toStringAsFixed(1)}°',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Kompas: ${_currentDirection.toStringAsFixed(1)}°',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
